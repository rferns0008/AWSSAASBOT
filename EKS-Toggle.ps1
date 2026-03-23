param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop")]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$ClusterName
)

# 1. Fetch all nodegroups forcing JSON output to avoid config errors
Write-Host "Fetching nodegroups for $ClusterName..." -ForegroundColor Gray
$rawJson = aws eks list-nodegroups --cluster-name $ClusterName --output json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to connect to AWS. Check your credentials and Cluster Name."
    exit
}

$nodegroups = $rawJson | ConvertFrom-Json

if ($null -eq $nodegroups.nodegroups -or $nodegroups.nodegroups.Count -eq 0) {
    Write-Warning "No managed nodegroups found for cluster $ClusterName."
    Write-Host "Note: This script only targets Managed Node Groups, not Self-Managed or Fargate."
    exit
}

foreach ($ng in $nodegroups.nodegroups) {
    if ($Action -eq "stop") {
        Write-Host "Stopping NodeGroup: $ng" -ForegroundColor Yellow
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=0,desiredSize=0 --output json
    }
    else {
        Write-Host "Starting NodeGroup: $ng" -ForegroundColor Green
        # Adjust these numbers to your preferred dev environment size
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=1,desiredSize=1 --output json
    }
}

Write-Host "Update command sent successfully. It may take a few minutes for EC2 instances to cycle." -ForegroundColor White