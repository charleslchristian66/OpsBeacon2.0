[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$checks=New-Object 'Collections.Generic.List[object]'
function Check($Name,$Passed){$checks.Add(@{name=$Name;passed=[bool]$Passed});if(-not $Passed){throw "FAILED: $Name"}}
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/LocalCollector.psm1'),[ref]$tokens,[ref]$parseErrors)
Check 'Collector parses in Windows PowerShell 5.1' ($parseErrors.Count -eq 0)
$helper=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-BeaconPendingReboot'},$true)
Invoke-Expression $helper.Extent.Text
$clear=Read-BeaconPendingReboot -ReadIndicator {param($i) $false}
Check 'All absent indicators produce Healthy and false' ($clear.status -eq 'Healthy' -and $clear.pending -eq $false -and $clear.coverage -eq 'Collected' -and $clear.indicators.Count -eq 4)
Check 'Evidence includes UTC collection time and registry paths' ($clear.checkedAtUtc.EndsWith('Z') -and @($clear.indicators | Where-Object registryPath -like 'HKLM\*').Count -eq 4)
foreach($name in @('Component Based Servicing','Windows Update','Pending file rename operations','Additional pending file rename operations')){
    $script:positiveIndicator=$name
    $r=Read-BeaconPendingReboot -ReadIndicator {param($i) $i.name -eq $script:positiveIndicator}
    Check "$name alone produces Warning and its reason" ($r.pending -eq $true -and $r.status -eq 'Warning' -and $r.reasons.Count -eq 1 -and $r.reasons[0] -eq $name)
}
$r=Read-BeaconPendingReboot -ReadIndicator {param($i) throw 'Access denied'}
Check 'Denied access is Unknown, never Healthy or false' ($null -eq $r.pending -and $r.status -eq 'Not Assessed' -and $r.coverage -eq 'Partial' -and @($r.indicators | Where-Object error -eq 'Access denied').Count -eq 4)
$r=Read-BeaconPendingReboot -ReadIndicator {param($i) if($i.name -eq 'Windows Update'){throw 'Access denied'};$false}
Check 'One unreadable indicator prevents a clear result' ($null -eq $r.pending -and $r.coverage -eq 'Partial')
$r=Read-BeaconPendingReboot -ReadIndicator {param($i) if($i.name -eq 'Windows Update'){throw 'Access denied'};$true}
Check 'Positive evidence remains Warning with partial coverage' ($r.pending -eq $true -and $r.status -eq 'Warning' -and $r.coverage -eq 'Partial' -and $r.reasons.Count -eq 3)
$r=Read-BeaconPendingReboot -ReadIndicator {param($i) 'invalid'}
Check 'Invalid reader result is unavailable' ($null -eq $r.pending -and $r.status -eq 'Not Assessed')
$live=Read-BeaconPendingReboot
Check 'Actual registry snapshot contains all indicator results' ($live.indicators.Count -eq 4 -and $live.status -in @('Healthy','Warning','Not Assessed'))
$live | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $PSScriptRoot 'reboot-live-results.json') -Encoding UTF8
$checks | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'reboot-results.json') -Encoding UTF8
$checks | ForEach-Object {[pscustomobject]$_} | Format-Table -AutoSize
