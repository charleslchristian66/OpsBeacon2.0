[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$stop=Join-Path $root 'Stop-OpsBeacon.ps1';$launcher=Join-Path $root 'Start-OpsBeacon.ps1'
$checks=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Passed){$checks.Add(@{name=$Name;passed=$Passed});if(-not $Passed){throw "FAILED: $Name"}}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($stop,[ref]$tokens,[ref]$errors)
Check 'Stop script parses on Windows PowerShell' ($errors.Count -eq 0)
foreach($name in @('Test-BeaconLauncher','Get-BeaconDescendants')){
    $definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
$now=Get-Date
$owner=[pscustomobject]@{Name='powershell.exe';ProcessId=123;CommandLine="powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcher`"";CreationDate=$now}
Check 'Exact dedicated deployment launcher is recognized' (Test-BeaconLauncher $owner $launcher $null)
$other=$owner.PSObject.Copy();$other.CommandLine='powershell.exe -File C:\Other\Start-OpsBeacon.ps1'
Check 'Another deployment with the same filename is refused' (-not (Test-BeaconLauncher $other $launcher $null))
$other.CommandLine="powershell.exe -Command Write-Host '-File $launcher'"
Check 'A launcher path embedded in another command is refused' (-not (Test-BeaconLauncher $other $launcher $null))
$other.CommandLine='powershell.exe -File .\Start-OpsBeacon.ps1'
Check 'Unproven relative launcher is refused' (-not (Test-BeaconLauncher $other $launcher $null))
$registration=@{processId=123;scriptPath=$launcher;startedUtc=$now.ToUniversalTime().ToString('o')}
Check 'Relative launcher is accepted with this deployment launch record' (Test-BeaconLauncher $other $launcher $registration)
$registration.startedUtc=$now.AddMinutes(-1).ToUniversalTime().ToString('o')
Check 'Stale launch record cannot authorize a reused PID' (-not (Test-BeaconLauncher $other $launcher $registration))
$tree=@([pscustomobject]@{Name='powershell.exe';ProcessId=124;ParentProcessId=123;CreationDate=$now.AddSeconds(1)},[pscustomobject]@{Name='powershell.exe';ProcessId=125;ParentProcessId=500;CreationDate=$now.AddSeconds(1)},[pscustomobject]@{Name='powershell.exe';ProcessId=126;ParentProcessId=123;CreationDate=$now.AddMinutes(-1)})
$children=@(Get-BeaconDescendants $owner $tree)
Check 'Only current descendants are selected as assessment workers' ($children.Count -eq 1 -and $children[0].ProcessId -eq 124)
$probe=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
$scratch=Join-Path $root "jobs/stop-check-$([guid]::NewGuid().ToString('N'))";New-Item -ItemType Directory -Path $scratch | Out-Null
$before=@(Get-ChildItem (Join-Path $root 'reports') -Filter '*.json' -File | Get-FileHash -Algorithm SHA256)
$server=$null;$unrelated=$null
try{
    # Relative -File exercises the new launch record while leaving the real 8080 server alone.
    $server=Start-Process powershell.exe -WorkingDirectory $root -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File .\Start-OpsBeacon.ps1 -Port $port" -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $scratch 'server.out') -RedirectStandardError (Join-Path $scratch 'server.err')
    $deadline=[datetime]::UtcNow.AddSeconds(90);$config=$null
    do{
        try{$config=Invoke-RestMethod "http://127.0.0.1:$port/api/config" -TimeoutSec 2}catch{}
        if($config){break};if($server.HasExited){throw (Get-Content (Join-Path $scratch 'server.err') -Raw)}
        if([datetime]::UtcNow -gt $deadline){throw 'Test server startup timed out'};Start-Sleep -Milliseconds 250
    }while($true)
    Check 'Isolated test server starts with a launch record' (Test-Path -LiteralPath (Join-Path $root "jobs/launcher-$($server.Id).json"))
    $body=@{target=$config.target;execution='local';profile='General Purpose Server';observationSeconds=300;sql=$false;cluster=$false;events=$false;connectivity=$false;destinations=@()} | ConvertTo-Json
    $job=Invoke-RestMethod "http://127.0.0.1:$port/api/jobs/assess" -Method Post -Headers @{'X-OpsBeacon-Live'='1'} -ContentType 'application/json' -Body $body
    $deadline=[datetime]::UtcNow.AddSeconds(30)
    do{
        $state=Invoke-RestMethod "http://127.0.0.1:$port$($job.pollUrl)"
        if($state.state -eq 'Running'){break};if($state.state -eq 'Failed'){throw $state.Error}
        if([datetime]::UtcNow -gt $deadline){throw 'Test worker startup timed out'};Start-Sleep -Milliseconds 250
    }while($true)
    $workerId=$state.pid
    & $stop -Port $port -WhatIf
    Check 'WhatIf leaves the listener and active worker running' ((Get-Process -Id $workerId -ErrorAction SilentlyContinue) -and @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count -gt 0)
    & $stop -Port $port -Confirm:$false
    Check 'Stop releases the isolated listener port' (@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count -eq 0)
    $worker=Get-Process -Id $workerId -ErrorAction SilentlyContinue
    if($worker){$null=$worker.WaitForExit(5000)}
    Check 'Stop removes the associated native assessment worker' (-not (Get-Process -Id $workerId -ErrorAction SilentlyContinue))
    $interrupted=Get-Content -LiteralPath (Join-Path $root "jobs/$($job.id).status.json") -Raw | ConvertFrom-Json
    Check 'Interrupted active job is recorded as Failed with its ID retained' ($interrupted.state -eq 'Failed' -and $interrupted.id -eq $job.id -and $interrupted.completedAt -and $interrupted.Error -like '*interrupted*')
    & $stop -Port $port
    Check 'Repeated stop is harmless when the port is free' (@(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count -eq 0)
    $stub=Join-Path $scratch 'Unrelated.ps1'
    Set-Content -LiteralPath $stub -Value 'param($Port) $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,[int]$Port);$listener.Start();try{while($true){Start-Sleep 1}}finally{$listener.Stop()}'
    $unrelated=Start-Process powershell.exe -ArgumentList "-NoProfile -File `"$stub`" $port" -WindowStyle Hidden -PassThru
    $deadline=[datetime]::UtcNow.AddSeconds(15)
    while(-not @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count){if([datetime]::UtcNow -gt $deadline){throw 'Unrelated test listener startup timed out'};Start-Sleep -Milliseconds 250}
    $refused=$false;try{& $stop -Port $port}catch{$refused=$_.Exception.Message -like '*Nothing was stopped*'}
    Check 'Unrelated live application on the requested port is refused and preserved' ($refused -and -not $unrelated.HasExited -and @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue).Count -gt 0)
    $changed=@($before | Where-Object {(Get-FileHash -LiteralPath $_.Path -Algorithm SHA256).Hash -ne $_.Hash})
    Check 'All existing saved reports are unchanged' ($changed.Count -eq 0)
}finally{
    foreach($process in @($unrelated,$server)){if($process -and -not $process.HasExited){Stop-Process -InputObject $process -ErrorAction SilentlyContinue}}
}
$checks | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'stop-results.json') -Encoding UTF8
$checks | ForEach-Object {[pscustomobject]$_} | Format-Table -AutoSize
