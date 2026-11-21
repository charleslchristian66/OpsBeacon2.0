[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;$source=[Environment]::MachineName
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/TargetWorker.ps1'),[ref]$t,[ref]$e)
$zoneDefinition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-BeaconTimeZone'},$true)
. ([scriptblock]::Create($zoneDefinition.Extent.Text))
$definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-BeaconEvents'},$true)
. ([scriptblock]::Create($definition.Extent.Text))
$summaryDefinition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-BeaconErrorSummary'},$true)
. ([scriptblock]::Create($summaryDefinition.Extent.Text))
$anchor=Get-WinEvent -LogName System -MaxEvents 1 -ErrorAction Stop
$time=$anchor.TimeCreated.ToUniversalTime()
$r=Read-BeaconEvents @{start=$time.AddMinutes(-1).ToString('o');end=$time.AddMinutes(1).ToString('o');logs=@('System');maxEvents=100;eventId=$anchor.Id}
$checks=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Passed){$checks.Add(@{name=$Name;passed=$Passed});if(-not $Passed){throw "FAILED: $Name"}}
Check 'UTC event query contains the known anchor occurrence' (@($r.events | Where-Object recordId -eq $anchor.RecordId).Count -eq 1)
Check 'UTC event window returns no out-of-window occurrences' (@($r.events | Where-Object {[datetime]::Parse($_.timestamp).ToUniversalTime() -lt $time.AddMinutes(-1) -or [datetime]::Parse($_.timestamp).ToUniversalTime() -gt $time.AddMinutes(1)}).Count -eq 0)
Check 'Event ID search retains distinct record identities' (@($r.events.key | Sort-Object -Unique).Count -eq $r.events.Count -and @($r.events | Where-Object eventId -ne $anchor.Id).Count -eq 0)
Check 'Original event timezone and actual source are retained' ($r.source -eq $source -and $r.events[0].originalTimeZone -and $r.events[0].simulated -eq $false)
$begin=[datetime]::UtcNow.AddHours(-24);$end=[datetime]::UtcNow
$summary=Read-BeaconErrorSummary @{start=$begin.ToString('o');end=$end.ToString('o');summaryLimit=20000}
foreach($log in @('System','Application')){
    $expected=@(Get-WinEvent -FilterHashtable @{LogName=$log;StartTime=$begin.ToLocalTime();EndTime=$end.ToLocalTime();Level=@(1,2)} -MaxEvents 20000 -ErrorAction SilentlyContinue)
    $actualCount=($summary.groups | Where-Object log -eq $log | Measure-Object count -Sum).Sum
    Check "Error summary count matches real $log errors" ([int]$actualCount -eq $expected.Count -and @($summary.searches | Where-Object {$_.log -eq $log -and $_.status -eq 'Collected'}).Count -eq 1)
    foreach($group in @($summary.groups | Where-Object log -eq $log)){
        Check "Source and Event ID count: $log / $($group.provider) / $($group.eventId)" ($group.count -eq @($expected | Where-Object {$_.ProviderName -eq $group.provider -and $_.Id -eq $group.eventId}).Count)
    }
}
if($summary.groups.Count){
    foreach($summaryGroup in $summary.groups){
        $resolved=Read-BeaconEvents @{start=$begin.ToString('o');end=$end.ToString('o');logs=@($summaryGroup.log);eventId=$summaryGroup.eventId;provider=$summaryGroup.provider;errorsOnly=$true;maxEvents=5000}
        Check "Every summary source resolves: $($summaryGroup.log) / $($summaryGroup.provider) / $($summaryGroup.eventId)" ($resolved.events.Count -eq [math]::Min(5000,$summaryGroup.count) -and @($resolved.searches | Where-Object status -ne 'Collected').Count -eq 0 -and @($resolved.events | Where-Object {$_.provider -ne $summaryGroup.provider -or $_.eventId -ne $summaryGroup.eventId -or $_.log -ne $summaryGroup.log}).Count -eq 0)
        if([string]::IsNullOrWhiteSpace($summaryGroup.latest.message)){
            Check "Missing provider description retains stored event data: $($summaryGroup.provider)" (@($resolved.events | Where-Object {[string]::IsNullOrWhiteSpace($_.message)}).Count -eq 0)
        }
    }
    $group=$summary.groups[0]
    $occurrences=Read-BeaconEvents @{start=$begin.ToString('o');end=$end.ToString('o');logs=@($group.log);eventId=$group.eventId;provider=$group.provider;errorsOnly=$true;maxEvents=5000}
    Check 'Summary group resolves only matching error occurrences' ($occurrences.events.Count -gt 0 -and @($occurrences.events | Where-Object {$_.provider -ne $group.provider -or $_.eventId -ne $group.eventId -or $_.log -ne $group.log -or $_.severity -notin @('Critical','Error')}).Count -eq 0)
    $anchor=$occurrences.events[-1];$center=[datetime]::Parse($anchor.timestamp).ToUniversalTime()
    $timeline=Read-BeaconEvents @{start=$center.AddHours(-2).ToString('o');end=$center.AddHours(2).ToString('o');logs=@('System','Application');maxEvents=5000}
    Check 'Cross-log timeline preserves the selected occurrence' (@($timeline.events | Where-Object key -eq $anchor.key).Count -eq 1)
    Check 'Timeline stays within plus or minus two hours' (@($timeline.events | Where-Object {[datetime]::Parse($_.timestamp).ToUniversalTime() -lt $center.AddHours(-2) -or [datetime]::Parse($_.timestamp).ToUniversalTime() -gt $center.AddHours(2)}).Count -eq 0)
    Check 'Timeline queries both logs without severity or ID filtering' ($timeline.searches.Count -eq 2 -and -not $timeline.errorsOnly -and $null -eq $timeline.eventId -and -not $timeline.provider)
    $limited=Read-BeaconEvents @{start=$center.AddHours(-2).ToString('o');end=$center.AddHours(2).ToString('o');logs=@('System','Application');maxEvents=1}
    Check 'Truncated timeline reports an honest lower bound' ($limited.truncated -and $limited.events.Count -eq 1 -and $limited.totalMatchingAtLeast -gt $limited.events.Count)
    $limitedSummary=Read-BeaconErrorSummary @{start=$begin.ToString('o');end=$end.ToString('o');summaryLimit=1}
    Check 'Error scan cap marks summary counts partial' ($limitedSummary.truncated -and ($limitedSummary.groups | Measure-Object count -Sum).Sum -le 2)
}
$empty=Read-BeaconEvents @{start=$end.AddDays(1).ToString('o');end=$end.AddDays(1).AddMinutes(1).ToString('o');logs=@('System','Application');maxEvents=5}
Check 'An empty period is collected with zero events' ($empty.events.Count -eq 0 -and $empty.totalMatchingAtLeast -eq 0 -and @($empty.searches | Where-Object status -ne 'Collected').Count -eq 0)
foreach($name in @("Missing'Publisher",'Missing"Publisher',"Missing'And`"Publisher")){
    $absent=Read-BeaconEvents @{start=$end.AddMinutes(-5).ToString('o');end=$end.ToString('o');logs=@('System');provider=$name;maxEvents=5}
    Check "Quoted missing source is an exact empty search: $name" ($absent.events.Count -eq 0 -and @($absent.searches | Where-Object status -ne 'Collected').Count -eq 0)
}
$checks | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'event-results.json') -Encoding UTF8
$checks | ForEach-Object {[pscustomobject]$_} | Format-Table -AutoSize
