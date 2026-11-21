[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot;$source=[Environment]::MachineName
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src/TargetWorker.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw ($parseErrors.Message -join '; ')}
$definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-BeaconTimeZone'},$true)
. ([scriptblock]::Create($definition.Extent.Text))
$checks=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Passed){$checks.Add(@{name=$Name;passed=$Passed});if(-not $Passed){throw "FAILED: $Name"}}
function Matches-Windows($Snapshot,[TimeZoneInfo]$Zone,[datetime]$Time){
    $period=@($Snapshot.periods | Where-Object {$Time -ge [datetime]::Parse($_.startUtc).ToUniversalTime() -and $Time -lt [datetime]::Parse($_.endUtc).ToUniversalTime()})
    return $period.Count -eq 1 -and $period[0].offsetMinutes -eq $Zone.GetUtcOffset($Time).TotalMinutes -and $period[0].daylight -eq $Zone.IsDaylightSavingTime($Time)
}
foreach($id in @('Eastern Standard Time','AUS Eastern Standard Time','India Standard Time','UTC')){
    $zone=[TimeZoneInfo]::FindSystemTimeZoneById($id);$snapshot=Read-BeaconTimeZone -Zone $zone
    Check "Target zone identity and UTC period endpoints retained: $id" ($snapshot.id -eq $id -and $snapshot.source -eq $source -and @($snapshot.periods | Where-Object {$_.startUtc -notmatch 'Z$' -or $_.endUtc -notmatch 'Z$'}).Count -eq 0)
    $matches=$true
    foreach($period in $snapshot.periods){
        foreach($instant in @([datetime]::Parse($period.startUtc).ToUniversalTime(),[datetime]::Parse($period.endUtc).ToUniversalTime().AddMilliseconds(-1))){
            if(-not (Matches-Windows $snapshot $zone $instant)){$matches=$false}
        }
    }
    Check "Every standard/daylight boundary matches Windows including both sides: $id" $matches
}
$local=Read-BeaconTimeZone
Check 'Actual target zone captured independently of event capability' ($local.id -eq [TimeZoneInfo]::Local.Id -and (Matches-Windows $local ([TimeZoneInfo]::Local) ([datetime]::UtcNow)))
$historical=[datetime]::SpecifyKind((New-Object datetime 2001,3,31),[DateTimeKind]::Utc)
$eastern=[TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
$older=Read-BeaconTimeZone -StartUtc $historical -EndUtc $historical.AddDays(7) -Zone $eastern
Check 'Older query windows include historical offset coverage' (Matches-Windows $older $eastern $historical.AddDays(1))
$fixed=[TimeZoneInfo]::CreateCustomTimeZone('DST disabled',[timespan]::FromHours(-5),'DST disabled','DST disabled')
$disabled=Read-BeaconTimeZone -Zone $fixed
Check 'Fixed target setting never invents daylight saving time' (-not $disabled.supportsDaylightSavingTime -and $disabled.periods.Count -eq 1 -and $disabled.periods[0].offsetMinutes -eq -300)
$checks | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'time-zone-results.json') -Encoding UTF8
$checks | ForEach-Object {[pscustomobject]$_} | Format-Table -AutoSize
