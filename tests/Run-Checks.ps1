[CmdletBinding()]
param([string]$BaseUrl='http://127.0.0.1:8080')
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;$checks=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Passed){$checks.Add(@{name=$Name;passed=$Passed});if(-not $Passed){throw "FAILED: $Name"}}
function Rejects([scriptblock]$Action){try{& $Action | Out-Null;return $false}catch{return $true}}
$scripts=@(Get-ChildItem -LiteralPath $root -File -Filter '*.ps1')+@(Get-ChildItem -LiteralPath (Join-Path $root 'src') -File)+@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)
foreach($file in $scripts){$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$t,[ref]$e);Check "PowerShell parses: $($file.Name)" ($e.Count -eq 0)}
Import-Module (Join-Path $root 'src/Api.psm1') -Force
$info=Invoke-RestMethod "$BaseUrl/api/config" -TimeoutSec 15
Check 'Live API and local identity' ($info.mode -eq 'live' -and $info.target -eq [Environment]::MachineName)
$valid=@{target=$info.target;execution='local';observationSeconds=5;sql=$true;cluster=$true;events=$true;connectivity=$true;sqlInstance='Auto';destinations=@(@{host='127.0.0.1';port=([uri]$BaseUrl).Port;protocol='http'})}
$request=ConvertTo-BeaconRequest $valid $root 'assess'
Check 'All capabilities accepted as live inputs' ($request.options.sql -and $request.options.cluster -and $request.options.events -and $request.options.connectivity)
foreach($profile in @('General Purpose Server','Database Server','Cluster Node')){
    $data=$valid.Clone();$data.profile=$profile;Check "Server profile retained: $profile" ((ConvertTo-BeaconRequest $data $root 'assess').options.profile -eq $profile)
}
$bad=$valid.Clone();$bad.profile='Unknown';Check 'Unknown server profile rejected' (Rejects {ConvertTo-BeaconRequest $bad $root 'assess'})
$bad=$valid.Clone();$bad.target='OTHER-COMPUTER';Check 'Local collection cannot redirect to another identity' (Rejects {ConvertTo-BeaconRequest $bad $root 'assess'})
$bad=$valid.Clone();$bad.observationSeconds=901;Check 'Observation duration bounded' (Rejects {ConvertTo-BeaconRequest $bad $root 'assess'})
$bad=$valid.Clone();$bad.sqlInstance='server;Password=secret';Check 'SQL connection-string injection rejected' (Rejects {ConvertTo-BeaconRequest $bad $root 'assess'})
$bad=$valid.Clone();$bad.destinations=@(@{host='example.com/path';port=443;protocol='https'});Check 'Destination URLs and paths rejected' (Rejects {ConvertTo-BeaconRequest $bad $root 'assess'})
$bad=$valid.Clone();$bad.destinations=@(1..21 | ForEach-Object {@{host='localhost';port=443;protocol='https'}});Check 'Destination count bounded' (Rejects {ConvertTo-BeaconRequest $bad $root 'assess'})
$bad=$valid.Clone();$bad.logs=@('Security');$bad.start=[datetime]::UtcNow.AddHours(-1).ToString('o');$bad.end=[datetime]::UtcNow.ToString('o');Check 'Unapproved event logs rejected' (Rejects {ConvertTo-BeaconRequest $bad $root 'events'})
$body=$valid | ConvertTo-Json -Depth 10
Check 'Mutation without custom header rejected' (Rejects {Invoke-RestMethod "$BaseUrl/api/jobs/assess" -Method Post -ContentType 'application/json' -Body $body})
Check 'Cross-origin mutation rejected' (Rejects {Invoke-RestMethod "$BaseUrl/api/jobs/assess" -Method Post -ContentType 'application/json' -Headers @{'X-OpsBeacon-Live'='1';Origin='http://untrusted.invalid'} -Body $body})
Check 'Report traversal rejected' (Rejects {Invoke-RestMethod "$BaseUrl/api/reports/not-a-uuid"})
Check 'No simulated collectors shipped' (-not (Test-Path -LiteralPath (Join-Path $root 'public/assets/collectors.js')))
Check 'Bundled Pode and licenses available' ((Test-Path -LiteralPath (Join-Path $root 'vendor/Pode/2.13.4/Pode.psd1')) -and (Test-Path -LiteralPath (Join-Path $root 'vendor/Pode/2.13.4/LICENSE.txt')))
$reportFile=Get-ChildItem -LiteralPath (Join-Path $root 'reports') -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($reportFile){
    $r=Get-Content $reportFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    Check 'Saved live evidence identifies actual collection source' ($r.Mode -eq 'live' -and $r.Execution.liveExecutionEstablished -and -not $r.Execution.portalFallbackAllowed -and $r.Execution.actualSource)
    Check 'Events have distinct occurrence identities and real provenance' (@($r.Events | Where-Object {$_.simulated -ne $false -or -not $_.recordId -or -not $_.key}).Count -eq 0 -and @($r.Events.key | Sort-Object -Unique).Count -eq $r.Events.Count)
    Check 'Readable report endpoint available' ((Invoke-WebRequest -UseBasicParsing "$BaseUrl/assets/report.html?id=$($r.AssessmentId)").StatusCode -eq 200)
    Check 'Saved report round trip retains live mode' ((Invoke-RestMethod "$BaseUrl/api/reports/$($r.AssessmentId)").Mode -eq 'live')
}
$baseline=Join-Path (Split-Path -Parent $root) 'tests/original-files-baseline.json'
if(Test-Path -LiteralPath $baseline){$originals=Get-Content $baseline -Raw -Encoding UTF8 | ConvertFrom-Json;$changed=@($originals | Where-Object {-not (Test-Path -LiteralPath $_.Path) -or (Get-FileHash -LiteralPath $_.Path -Algorithm SHA256).Hash -ne $_.SHA256});Check "All $($originals.Count) original files preserved" ($changed.Count -eq 0)}
$checks | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'powershell-results.json') -Encoding UTF8
$checks | ForEach-Object {[pscustomobject]$_} | Format-Table -AutoSize
