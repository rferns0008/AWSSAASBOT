param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop")]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$ClusterName,

    [Parameter(Mandatory=$false)]
    [string]$Namespace = "chatbot-production"
)

# Replace with your actual ARN from the screenshot
$TargetGroupArn = "arn:aws:elasticloadbalancing:ap-south-1:078083578991:targetgroup/k8s-chatbotp-flaskcha-8b2747a29b/b9517e80f31fcc5a"

if ($Action -eq "stop") {
    Write-Host "`n[1/5] Reducing ALB Timeout to 60s..." -ForegroundColor Gray
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

    Write-Host "[4/5] Stopping System Controllers (No more Pending pods)..." -ForegroundColor Cyan
    kubectl scale deployment coredns -n kube-system --replicas=0
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=0

    Write-Host "[5/5] Terminating EC2 Instances..." -ForegroundColor Yellow
    $nodegroups = aws eks list-nodegroups --cluster-name $ClusterName --output json | ConvertFrom-Json
    foreach ($ng in $nodegroups.nodegroups) {
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=0,desiredSize=0 --output json | Out-Null
    }
    Write-Host "`nSUCCESS: Cluster is COLD and ALB is CLEAN." -ForegroundColor Green
}
else {
    Write-Host "`n[1/3] Provisioning Nodes..." -ForegroundColor Yellow
    $nodegroups = aws eks list-nodegroups --cluster-name $ClusterName --output json | ConvertFrom-Json
    foreach ($ng in $nodegroups.nodegroups) {
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=1,desiredSize=1 --output json | Out-Null
    }

    Write-Host "Waiting for Nodes to reach 'Ready' state..." -ForegroundColor Gray
    while ($true) {
        $nodes = kubectl get nodes --no-headers 2>$null
        if ($nodes -match "Ready") { break }
        Write-Host "." -NoNewline; Start-Sleep -Seconds 10
    }

    Write-Host "`n[2/3] Starting System Controllers..." -ForegroundColor Cyan
    kubectl scale deployment coredns -n kube-system --replicas=2
    kubectl scale deployment aws-load-balancer-controller -n kube-system --replicas=1
    Start-Sleep -Seconds 20 # Wait for Controller to link to AWS

    Write-Host "[3/3] Restoring Apps (Auto-Registering to ALB)..." -ForegroundColor Cyan
    kubectl scale deployment --all --replicas=1 -n $Namespace
    
    Write-Host "`nSUCCESS: Cluster is HOT. Check ALB for Healthy status." -ForegroundColor Green
}