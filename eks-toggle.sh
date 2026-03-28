#!/bin/bash

# --- Configuration ---
CLUSTER_NAME="secure-eks-testing"
TARGET_GROUP_ARN="arn:aws:elasticloadbalancing:ap-south-1:078083578991:targetgroup/k8s-chatbotp-flaskcha-8b2747a29b/b9517e80f31fcc5a"
ACTION=$1

# Validation
if [[ -z "$ACTION" || ! "$ACTION" =~ ^(start|stop)$ ]]; then
    echo "Usage: ./eks-toggle.sh [start|stop]"
    exit 1
fi

# Dynamically fetch all non-system namespaces
NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -vE 'kube-system|default|kube-public|kube-node-lease')

if [[ "$ACTION" == "stop" ]]; then
    echo -e "\n[1/5] Tuning ALB Timeout to 60s for clean removal..."
    aws elbv2 modify-target-group-attributes --target-group-arn "$TARGET_GROUP_ARN" --attributes Key=deregistration_delay.timeout_seconds,Value=60 --output json > /dev/null

    echo "[2/5] Scaling ALL Deployments to 0 (Killing PDB Blockers)..."
    # Scale system tools first to avoid drain hangs
    kubectl scale deployment coredns -n kube-system --replicas=0
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=0
    
    # Scale every other detected namespace
    for ns in $NAMESPACES; do
        echo "Scaling down namespace: $ns"
        kubectl scale deployment --all --replicas=0 -n "$ns"
    done

    echo "Waiting 65s for Pods to delete and ALB to clear 'Ghost' targets..."
    sleep 65

    echo "[3/5] Draining Nodes..."
    NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    for node in $NODES; do
        echo "Draining $node..."
        kubectl drain "$node" --force --ignore-daemonsets --delete-emptydir-data --grace-period=0
    done

    echo "[4/5] Terminating EC2 Infrastructure..."
    NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text)
    for ng in $NODEGROUPS; do
        aws eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --scaling-config minSize=0,desiredSize=0 --output json > /dev/null
    done
    echo -e "\nSUCCESS: Cluster is COLD. No pods or nodes lingering."

else
    echo -e "\n[1/3] Provisioning 2 Nodes..."
    NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text)
    for ng in $NODEGROUPS; do
        aws eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --scaling-config minSize=2,desiredSize=2 --output json > /dev/null
    done

    echo -n "Waiting for 2 Nodes to reach 'Ready' state..."
    while true; do
        # Silencing 'No resources found' errors during hardware boot
        READY_COUNT=$(kubectl get nodes 2>/dev/null | grep -c "Ready")
        if [[ "$READY_COUNT" -ge 2 ]]; then
            echo -e "\nBoth nodes are Ready!"
            break
        fi
        echo -n "."
        sleep 10
    done

    echo "[2/3] Restoring System Controllers..."
    kubectl scale deployment coredns -n kube-system --replicas=2
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=1
    
    # Give the LB controller time to re-establish AWS API connection
    sleep 20 

    echo "[3/3] Restoring ALL Application Namespaces..."
    for ns in $NAMESPACES; do
        echo "Scaling up namespace: $ns"
        kubectl scale deployment --all --replicas=1 -n "$ns"
    done
    
    echo -e "\nSUCCESS: Cluster is HOT. New targets are auto-registering to the ALB."
fi