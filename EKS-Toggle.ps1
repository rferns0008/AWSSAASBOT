param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop")]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$ClusterName
)

# Configuration - Update these for your environment
$Region = "ap-south-1"
$TargetGroupArn = "arn:aws:elasticloadbalancing:ap-south-1:078083578991:targetgroup/k8s-chatbotp-flaskcha-8b2747a29b/b9517e80f31fcc5a"

# --- Connection Fix ---
Write-Host "Checking EKS Connection..." -ForegroundColor Gray
aws eks update-kubeconfig --region $Region --name $ClusterName | Out-Null

# Get all non-system namespaces
$namespaces = (kubectl get namespaces -o json | ConvertFrom-Json).items | Where-Object { $_.metadata.name -ne "kube-system" -and $_.metadata.name -ne "default" } | Select-Object -ExpandProperty metadata | Select-Object -ExpandProperty name

if ($Action -eq "stop") {
    Write-Host "`n[1/5] Forcefully Clearing ALB Targets..." -ForegroundColor Cyan
    # Set deregistration delay to 60s to speed up the script
    aws elbv2 modify-target-group-attributes --target-group-arn $TargetGroupArn --attributes Key=deregistration_delay.timeout_seconds,Value=60 --output json | Out-Null
    
    foreach ($ns in $namespaces) {
        Write-Host "Scaling down $ns..."
        kubectl scale deployment --all --replicas=0 -n $ns
    }
    
    Write-Host "Waiting 65s for ALB Controller to deregister nodes from Target Group..." -ForegroundColor Yellow
    Start-Sleep -Seconds 65

    Write-Host "[2/5] Scaling System Controllers to 0..." -ForegroundColor Cyan
    kubectl scale deployment coredns -n kube-system --replicas=0
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=0

    Write-Host "[3/5] Draining Worker Nodes..." -ForegroundColor Cyan
    $nodes = (kubectl get nodes -o json | ConvertFrom-Json).items
    foreach ($node in $nodes) {
        Write-Host "Draining $($node.metadata.name)..."
        kubectl drain $($node.metadata.name) --force --ignore-daemonsets --delete-emptydir-data --grace-period=0
    }

    Write-Host "[4/5] Scaling EC2 Node Group to 0..." -ForegroundColor Yellow
    $nodegroups = aws eks list-nodegroups --cluster-name $ClusterName --output json | ConvertFrom-Json
    foreach ($ng in $nodegroups.nodegroups) {
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=0,desiredSize=0 --output json | Out-Null
    }
    Write-Host "`nSUCCESS: Cluster is COLD and ALB is EMPTY." -ForegroundColor Green
}
else {
    Write-Host "`n[1/3] Provisioning 2 Nodes..." -ForegroundColor Yellow
    $nodegroups = aws eks list-nodegroups --cluster-name $ClusterName --output json | ConvertFrom-Json
    foreach ($ng in $nodegroups.nodegroups) {
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=2,desiredSize=2 --output json | Out-Null
    }

    Write-Host "Waiting for 2 Nodes to reach 'Ready' state..." -ForegroundColor Gray
    while ($true) {
        $nodesCount = (kubectl get nodes --no-headers 2>$null | Select-String "Ready").Count
        if ($nodesCount -ge 2) { break }
        Write-Host "." -NoNewline; Start-Sleep -Seconds 10
    }

    Write-Host "`n[2/3] Restoring System & ALB Controller..." -ForegroundColor Cyan
    kubectl scale deployment coredns -n kube-system --replicas=2
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=1
    Start-Sleep -Seconds 30 # Allow controller to stabilize

    Write-Host "[3/3] Restoring All Application Namespaces..." -ForegroundColor Cyan
    foreach ($ns in $namespaces) {
        kubectl scale deployment --all --replicas=1 -n $ns
    }
    Write-Host "`nSUCCESS: Cluster is HOT." -ForegroundColor Green
}