param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop")]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$ClusterName
)

# Target Group ARN from your AWS Console
$TargetGroupArn = "arn:aws:elasticloadbalancing:ap-south-1:078083578991:targetgroup/k8s-chatbotp-flaskcha-8b2747a29b/b9517e80f31fcc5a"

# Get all non-system namespaces
$allNamespaces = (kubectl get namespaces -o json | ConvertFrom-Json).items | Where-Object { $_.metadata.name -ne "kube-system" -and $_.metadata.name -ne "default" } | Select-Object -ExpandProperty metadata | Select-Object -ExpandProperty name

if ($Action -eq "stop") {
    Write-Host "`n[1/5] Reducing ALB Timeout..." -ForegroundColor Gray
    aws elbv2 modify-target-group-attributes --target-group-arn $TargetGroupArn --attributes Key=deregistration_delay.timeout_seconds,Value=60 --output json | Out-Null

    Write-Host "[2/5] Scaling ALL Namespaces to 0 (Removing PDB Blockers)..." -ForegroundColor Cyan
    # Scale system tools first
    kubectl scale deployment coredns -n kube-system --replicas=0
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=0
    
    # Scale every other namespace found in the cluster
    foreach ($ns in $allNamespaces) {
        Write-Host "Scaling down namespace: $ns"
        kubectl scale deployment --all --replicas=0 -n $ns
    }

    Write-Host "Waiting 30s for Pods to clear..." -ForegroundColor Gray
    Start-Sleep -Seconds 30

    Write-Host "[3/5] Draining Nodes..." -ForegroundColor Cyan
    $nodes = (kubectl get nodes -o json | ConvertFrom-Json).items
    foreach ($node in $nodes) {
        Write-Host "Draining $($node.metadata.name)..."
        kubectl drain $($node.metadata.name) --force --ignore-daemonsets --delete-emptydir-data --grace-period=0
    }

    Write-Host "[4/5] Terminating EC2 Instances..." -ForegroundColor Yellow
    $nodegroups = aws eks list-nodegroups --cluster-name $ClusterName --output json | ConvertFrom-Json
    foreach ($ng in $nodegroups.nodegroups) {
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=0,desiredSize=0 --output json | Out-Null
    }
    Write-Host "`nSUCCESS: Cluster is COLD and all namespaces are cleared." -ForegroundColor Green
}
else {
    Write-Host "`n[1/3] Provisioning 2 Nodes..." -ForegroundColor Yellow
    $nodegroups = aws eks list-nodegroups --cluster-name $ClusterName --output json | ConvertFrom-Json
    foreach ($ng in $nodegroups.nodegroups) {
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=2,desiredSize=2 --output json | Out-Null
    }

    Write-Host "Waiting for 2 Nodes to reach 'Ready' state..." -ForegroundColor Gray
    while ($true) {
        $nodesCount = (kubectl get nodes --no-headers | Select-String "Ready").Count
        if ($nodesCount -ge 2) { break }
        Write-Host "." -NoNewline; Start-Sleep -Seconds 10
    }

    Write-Host "`n[2/3] Restoring System Controllers..." -ForegroundColor Cyan
    kubectl scale deployment coredns -n kube-system --replicas=2
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=1
    Start-Sleep -Seconds 20 

    Write-Host "[3/3] Restoring ALL Namespaces..." -ForegroundColor Cyan
    foreach ($ns in $allNamespaces) {
        Write-Host "Scaling up namespace: $ns"
        kubectl scale deployment --all --replicas=1 -n $ns
    }
    
    Write-Host "`nSUCCESS: Cluster is HOT and all apps are recovering." -ForegroundColor Green
}