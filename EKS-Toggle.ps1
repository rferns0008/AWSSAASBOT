param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop")]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$ClusterName
)

# 1. Fetch all nodegroups in the cluster
$nodegroups = aws eks list-nodegroups --cluster-name $ClusterName | ConvertFrom-Json

if ($null -eq $nodegroups.nodegroups) {
    Write-Error "No nodegroups found for cluster $ClusterName"
    exit
}

foreach ($ng in $nodegroups.nodegroups) {
    if ($Action -eq "stop") {
        Write-Host "Stopping NodeGroup: $ng" -ForegroundColor Cyan
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=0,desiredSize=0
    }
    else {
        Write-Host "Starting NodeGroup: $ng" -ForegroundColor Green
        # Note: adjust min/desired to your preference
        aws eks update-nodegroup-config --cluster-name $ClusterName --nodegroup-name $ng --scaling-config minSize=1,desiredSize=2
    }
}