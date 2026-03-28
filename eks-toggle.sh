#!/bin/bash

# Configuration
CLUSTER_NAME="secure-eks-testing"
TARGET_GROUP_ARN="arn:aws:elasticloadbalancing:ap-south-1:078083578991:targetgroup/k8s-chatbotp-flaskcha-8b2747a29b/b9517e80f31fcc5a"
ACTION=$1

if [[ -z "$ACTION" || ! "$ACTION" =~ ^(start|stop)$ ]]; then
    echo "Usage: ./eks-toggle.sh [start|stop]"
    exit 1
fi

# Fetch all non-system and non-default namespaces
NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -vE 'kube-system|default|kube-public|kube-node-lease')

if [[ "$ACTION" == "stop" ]]; then
    echo -e "\n[1/5] Reducing ALB Timeout to 60s..."
    aws elbv2 modify-target-group-attributes --target-group-arn "$TARGET_GROUP_ARN" --attributes Key=deregistration_delay.timeout_seconds,Value=60 --output json > /dev/null

    echo "[2/5] Scaling ALL Namespaces to 0 (Removing PDB Blockers)..."
    # Scale system tools first
    kubectl scale deployment coredns -n kube-system --replicas=0
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=0
    
    # Scale every other namespace found
    for ns in $NAMESPACES; do
        echo "Scaling down namespace: $ns"
        kubectl scale deployment --all --replicas=0 -n "$ns"
    done

    echo "Waiting 30s for Pods to clear..."
    sleep 30

    echo "[3/5] Draining Nodes..."
    NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    for node in $NODES; do
        echo "Draining $node..."
        kubectl drain "$node" --force --ignore-daemonsets --delete-emptydir-data --grace-period=0
    done

    echo "[4/5] Terminating EC2 Instances..."
    NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text)
    for ng in $NODEGROUPS; do
        aws eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --scaling-config minSize=0,desiredSize=0 --output json > /dev/null
    done
    echo -e "\nSUCCESS: Cluster is COLD and all namespaces are cleared."

else
    echo -e "\n[1/3] Provisioning 2 Nodes..."
    NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text)
    for ng in $NODEGROUPS; do
        aws eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --scaling-config minSize=2,desiredSize=2 --output json > /dev/null
    done

    echo -n "Waiting for 2 Nodes to reach 'Ready' state..."
    while true; do
        READY_COUNT=$(kubectl get nodes | grep -c "Ready")
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
    sleep 20 

    echo "[3/3] Restoring ALL Namespaces..."
    for ns in $NAMESPACES; do
        echo "Scaling up namespace: $ns"
        kubectl scale deployment --all --replicas=1 -n "$ns"
    done
    
    echo -e "\nSUCCESS: Cluster is HOT and all apps are recovering."
fi