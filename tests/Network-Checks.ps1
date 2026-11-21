[CmdletBinding()]
param([int]$Port=8080)
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;$source=[Environment]::MachineName
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/TargetWorker.ps1'),[ref]$t,[ref]$e)
$definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-BeaconNetwork'},$true)
. ([scriptblock]::Create($definition.Extent.Text))
$parallel=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-BeaconParallelNetwork'},$true)
. ([scriptblock]::Create($parallel.Extent.Text))
$config=Get-Content (Join-Path $root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$checks=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Passed){$checks.Add(@{name=$Name;passed=$Passed});if(-not $Passed){throw "FAILED: $Name"}}
$config.connectivity.latencyThresholdMs=-1 # Force the automatic trace branch against loopback only.
$r=@(Read-BeaconNetwork @(@{host='127.0.0.1';port=$Port;protocol='http'}) $config.connectivity)[0]
Check 'DNS, ICMP, TCP and HTTP run on the inspected source' ($r.sourceServer -eq $source -and $r.dns.status -eq 'Healthy' -and $r.ping.sent -eq 4 -and $r.tcp.connected -and $r.https.statusCode -eq 200)
Check 'Trace trigger causes exactly one bounded successful loopback trace' ($r.trace.attempted -and $r.trace.attemptCount -eq 1 -and $r.trace.reached -and $r.trace.hops.Count -eq 1 -and $r.trace.elapsedMs -lt 15000)
$config.connectivity.inspectionLimitSeconds=0
$limited=@(Read-BeaconNetwork @(@{host='127.0.0.1';port=$Port;protocol='http'}) $config.connectivity)[0]
Check 'Expired connectivity budget yields missing coverage and no probes' ($limited.truncated -and $limited.ping.sent -eq 0 -and $limited.dns.status -eq 'Not Assessed' -and $limited.error)
Check 'Original six concurrent probe workers configured' ($config.connectivity.maxConcurrent -eq 6)
$config.connectivity.inspectionLimitSeconds=60
$destinations=@(1..6 | ForEach-Object {@{host='127.0.0.1';port=$Port;protocol='http'}})
$parallelResults=@(Invoke-BeaconParallelNetwork $destinations $config.connectivity)
Check 'Parallel workers return all destination results with actual source' ($parallelResults.Count -eq 6 -and @($parallelResults | Where-Object {$_.error -or $_.sourceServer -ne $source -or $_.https.statusCode -ne 200 -or $_.ping.sent -ne 4}).Count -eq 0)
Check 'Parallel traces remain bounded per destination' (@($parallelResults | Where-Object {-not $_.trace.reached -or $_.trace.attemptCount -ne 1 -or $_.trace.hops.Count -ne 1}).Count -eq 0)
$config.connectivity.inspectionLimitSeconds=0
$expired=@(Invoke-BeaconParallelNetwork $destinations $config.connectivity)
Check 'Shared inspection deadline prevents queued probes after expiry' ($expired.Count -eq 6 -and @($expired | Where-Object {-not $_.truncated -or $_.ping.sent -ne 0}).Count -eq 0)

# A shared gate measures real overlap without sending traffic to remote systems.
$realProbe=${function:Read-BeaconNetwork}
try{
    function Read-BeaconNetwork($Destinations,$Limits,$DeadlineUtc){
        [Threading.Monitor]::Enter($Limits.Gate.SyncRoot)
        try{$Limits.Gate.Active++;$Limits.Gate.Peak=[math]::Max($Limits.Gate.Active,$Limits.Gate.Peak)}finally{[Threading.Monitor]::Exit($Limits.Gate.SyncRoot)}
        try{Start-Sleep -Milliseconds 500;[pscustomobject]@{host=$Destinations[0].host;sourceServer=$source}}finally{
            [Threading.Monitor]::Enter($Limits.Gate.SyncRoot)
            try{$Limits.Gate.Active--}finally{[Threading.Monitor]::Exit($Limits.Gate.SyncRoot)}
        }
    }
    $gate=[hashtable]::Synchronized(@{Active=0;Peak=0})
    $measured=@(Invoke-BeaconParallelNetwork (@($destinations)+@($destinations)) @{maxConcurrent=6;inspectionLimitSeconds=60;Gate=$gate})
    Check 'Probe runspaces overlap and honor the six-worker limit' ($measured.Count -eq 12 -and $gate.Peak -gt 1 -and $gate.Peak -le 6 -and $gate.Active -eq 0)
}finally{Set-Item -Path Function:\Read-BeaconNetwork -Value $realProbe}
$checks | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'network-results.json') -Encoding UTF8
$checks | ForEach-Object {[pscustomobject]$_} | Format-Table -AutoSize
