param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop")]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$ClusterName,

    [Parameter(Mandatory=$false)]
    [string]$Namespace = "chatbot-production"
)

# Target Group ARN from your AWS Console
$TargetGroupArn = "arn:aws:elasticloadbalancing:ap-south-1:078083578991:targetgroup/k8s-chatbotp-flaskcha-8b2747a29b/b9517e80f31fcc5a"

if ($Action -eq "stop") {
    Write-Host "`n[1/5] Reducing ALB Timeout to 60s for clean removal..." -ForegroundColor Gray
    aws elbv2 modify-target-group-attributes --target-group-arn $TargetGroupArn --attributes Key=deregistration_delay.timeout_seconds,Value=60 --output json | Out-Null

    Write-Host "[2/5] Scaling Apps to 0 (Deregistering from ALB)..." -ForegroundColor Cyan
    kubectl scale deployment --all --replicas=0 -n $Namespace

    Write-Host "Waiting 65s for ALB to clear targets..." -ForegroundColor Gray
    Start-Sleep -Seconds 65

    Write-Host "[3/5] Draining Nodes..." -ForegroundColor Cyan
    $nodes = (kubectl get nodes -o json | ConvertFrom-Json).items
    foreach ($node in $nodes) {
        Write-Host "Draining $($node.metadata.name)..."
        kubectl drain $($node.metadata.name) --force --ignore-daemonsets --delete-emptydir-data --grace-period=30
    }

    Write-Host "[4/5] Stopping System Controllers (No Pending pods)..." -ForegroundColor Cyan
    kubectl scale deployment coredns -n kube-system --replicas=0
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=0

    Write-Host "[5/5] Terminating EC2 Instances..." -ForegroundColor Yellow
    $nodegroups = aws eks list-nodegroups --cluster-name $ClusterName --output json | ConvertFrom-Json
    foreach ($ng in $nodegroups.nodegroups) {
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=0,desiredSize=0 --output json | Out-Null
    }
    Write-Host "`nSUCCESS: Cluster is COLD." -ForegroundColor Green
}
else {
    Write-Host "`n[1/3] Provisioning 2 Nodes..." -ForegroundColor Yellow
    $nodegroups = aws eks list-nodegroups --cluster-name $ClusterName --output json | ConvertFrom-Json
    foreach ($ng in $nodegroups.nodegroups) {
        # CHANGED: minSize and desiredSize set to 2
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=2,desiredSize=2 --output json | Out-Null
    }

    Write-Host "Waiting for 2 Nodes to reach 'Ready' state..." -ForegroundColor Gray
    while ($true) {
        $nodesCount = (kubectl get nodes --no-headers | Select-String "Ready").Count
        if ($nodesCount -ge 2) { 
            Write-Host "`nBoth nodes are Ready!" -ForegroundColor Green
            break 
        }
        Write-Host "." -NoNewline; Start-Sleep -Seconds 10
    }

    Write-Host "`n[2/3] Starting System Controllers..." -ForegroundColor Cyan
    kubectl scale deployment coredns -n kube-system --replicas=2
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=1
    Start-Sleep -Seconds 20 

    Write-Host "[3/3] Restoring Apps (ALB will auto-register)..." -ForegroundColor Cyan
    kubectl scale deployment --all --replicas=1 -n $Namespace
    
    Write-Host "`nSUCCESS: Cluster is HOT with 2 nodes." -ForegroundColor Green
}