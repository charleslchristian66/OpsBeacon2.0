[CmdletBinding()]
param()
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$checks=New-Object 'Collections.Generic.List[object]'
function Check($Name,$Passed){$checks.Add(@{name=$Name;passed=[bool]$Passed});if(-not $Passed){throw "FAILED: $Name"}}
$path=Join-Path $root 'src/LocalCollector.psm1';$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
Check 'Collector parses in Windows PowerShell 5.1' ($parseErrors.Count -eq 0)
Import-Module $path -Force
$live=Invoke-BeaconLocalCollection -ObservationSeconds 3
$expected=@(Get-CimInstance Win32_Volume -OperationTimeoutSec 10 | Where-Object DriveLetter)
foreach($disk in $expected){
    $actual=@($live.Measurements.volumes | Where-Object id -eq $disk.DeviceID)
    Check "Live capacity includes $($disk.DriveLetter) exactly once" ($actual.Count -eq 1 -and $actual[0].totalBytes -eq $disk.Capacity)
    Check "Live $($disk.DriveLetter) byte accounting is consistent" ($actual[0].usedBytes+$actual[0].freeBytes -eq $actual[0].totalBytes)
}
Check 'Legacy system-drive capacity retained' ($null -ne $live.Measurements.diskTotalGB)
Check 'Live volume discovery completed' ($live.Measurements.volumeCapacityStatus -eq 'Collected')
$live | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $PSScriptRoot 'volume-live-results.json') -Encoding UTF8
$definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Read-BeaconVolumes'},$true).Extent.Text
& {
    Invoke-Expression $definition
    $script:failVolumes=$false;$script:failMounts=$false
    function Get-CimInstance {
        param($Namespace,$ClassName,$Filter,$OperationTimeoutSec,$ErrorAction)
        if($ClassName -eq 'Win32_LogicalDisk'){return [pscustomobject]@{DeviceID='Z:';VolumeName='Mapped';FileSystem='NTFS';Size=1000;FreeSpace=400}}
        if($script:failVolumes){throw 'Discovery denied'}
        @(
            [pscustomobject]@{DeviceID='system';DriveLetter='C:';Name='C:\';Label='OS';FileSystem='NTFS';DriveType=3;Capacity=1000;FreeSpace=100},
            [pscustomobject]@{DeviceID='folder';DriveLetter=$null;Name='C:\Data\';Label='Data';FileSystem='ReFS';DriveType=3;Capacity=2000;FreeSpace=0},
            [pscustomobject]@{DeviceID='hidden';DriveLetter=$null;Name='\\?\Volume{hidden}\';DriveType=3;Capacity=100;FreeSpace=50},
            [pscustomobject]@{DeviceID='empty';DriveLetter='E:';Name='E:\';DriveType=5;Capacity=$null;FreeSpace=$null}
        )
    }
    function Get-CimAssociatedInstance {
        param($InputObject,$Association,$ResultClassName,$OperationTimeoutSec,$ErrorAction)
        if($script:failMounts){throw 'Mount discovery denied'}
        if($InputObject.DeviceID -eq 'folder'){
            [pscustomobject]@{Name='C:\Data'};[pscustomobject]@{Name='D:\Alias'}
        }
    }
    $result=Read-BeaconVolumes
    Check 'Folder-mounted volume is included once with all aliases' (@($result.volumes | Where-Object id -eq folder).Count -eq 1 -and @($result.volumes | Where-Object id -eq folder)[0].mountPaths.Count -eq 2)
    Check 'Unmounted hidden partitions excluded' (@($result.volumes | Where-Object id -eq hidden).Count -eq 0)
    $full=@($result.volumes | Where-Object id -eq folder)[0]
    Check 'Full volume remains measured zero free space' ($full.freeBytes -eq 0 -and $full.freePercent -eq 0 -and -not $full.error)
    $empty=@($result.volumes | Where-Object id -eq empty)[0]
    Check 'Missing media does not become zero capacity or Healthy' ($null -eq $empty.totalBytes -and $null -eq $empty.freePercent -and $empty.error)
    Check 'Visible mapped network drive included' (@($result.volumes | Where-Object id -eq 'Z:').Count -eq 1)
    $script:failVolumes=$true;$failed=Read-BeaconVolumes
    Check 'Volume discovery failure is explicit partial coverage' ($failed.status -eq 'Partial' -and $failed.errors.Count -gt 0)
    $script:failVolumes=$false;$script:failMounts=$true;$partial=Read-BeaconVolumes
    Check 'Mount-path lookup failure preserves drive letters with explicit gap' ($partial.status -eq 'Partial' -and @($partial.volumes | Where-Object id -eq system).Count -eq 1)
}
$checks | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'volume-results.json') -Encoding UTF8
$checks | ForEach-Object {[pscustomobject]$_} | Format-Table -AutoSize
