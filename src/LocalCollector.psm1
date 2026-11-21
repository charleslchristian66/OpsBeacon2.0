function Read-BeaconVolumes {
    $volumes=New-Object 'Collections.Generic.List[object]'
    $errors=New-Object 'Collections.Generic.List[object]'
    $seen=@{}
    try {
        $localVolumes=@(Get-CimInstance -Namespace root/cimv2 -ClassName Win32_Volume -OperationTimeoutSec 10 -ErrorAction Stop)
        foreach($volume in $localVolumes){
            if($seen.ContainsKey([string]$volume.DeviceID)){continue}
            $seen[[string]$volume.DeviceID]=$true
            $paths=@()
            if($volume.DriveLetter){$paths+=[string]$volume.DriveLetter+'\'}
            if($volume.Name -and $volume.Name -notlike '\\?\Volume{*'){$paths+=[string]$volume.Name}
            try {
                $paths+=@(Get-CimAssociatedInstance -InputObject $volume -Association Win32_MountPoint -ResultClassName Win32_Directory -OperationTimeoutSec 10 -ErrorAction Stop | ForEach-Object {[string]$_.Name})
            }catch{$errors.Add([pscustomobject]@{scope='Volume mount paths';error="$($volume.DeviceID): $($_.Exception.Message)"})}
            $paths=@($paths | Where-Object {$_} | ForEach-Object {$_.TrimEnd('\')+'\'} | Sort-Object -Unique)
            # Unmounted recovery/system partitions have no user-accessible mount path.
            if(-not $paths.Count){continue}
            $valid=$null -ne $volume.Capacity -and $volume.Capacity -gt 0 -and $null -ne $volume.FreeSpace -and $volume.FreeSpace -ge 0 -and $volume.FreeSpace -le $volume.Capacity
            $volumes.Add([pscustomobject]@{
                id=[string]$volume.DeviceID;mountPaths=$paths;label=[string]$volume.Label;fileSystem=[string]$volume.FileSystem;driveType=[int]$volume.DriveType
                totalBytes=if($valid){[double]$volume.Capacity}else{$null};freeBytes=if($valid){[double]$volume.FreeSpace}else{$null}
                usedBytes=if($valid){[double]($volume.Capacity-$volume.FreeSpace)}else{$null}
                freePercent=if($valid){100.0*$volume.FreeSpace/$volume.Capacity}else{$null}
                error=if($valid){$null}else{'Capacity unavailable; the volume may be inaccessible or have no media.'}
            })
        }
    }catch{$errors.Add([pscustomobject]@{scope='Mounted volumes';error=$_.Exception.Message})}
    # Mapped network drives are visible only in the inspected execution identity/session.
    try {
        foreach($disk in @(Get-CimInstance -Namespace root/cimv2 -ClassName Win32_LogicalDisk -Filter 'DriveType=4' -OperationTimeoutSec 10 -ErrorAction Stop)){
            $valid=$null -ne $disk.Size -and $disk.Size -gt 0 -and $null -ne $disk.FreeSpace -and $disk.FreeSpace -ge 0 -and $disk.FreeSpace -le $disk.Size
            $volumes.Add([pscustomobject]@{
                id=[string]$disk.DeviceID;mountPaths=@([string]$disk.DeviceID+'\');label=[string]$disk.VolumeName;fileSystem=[string]$disk.FileSystem;driveType=4
                totalBytes=if($valid){[double]$disk.Size}else{$null};freeBytes=if($valid){[double]$disk.FreeSpace}else{$null}
                usedBytes=if($valid){[double]($disk.Size-$disk.FreeSpace)}else{$null};freePercent=if($valid){100.0*$disk.FreeSpace/$disk.Size}else{$null}
                error=if($valid){$null}else{'Network drive capacity unavailable in this execution session.'}
            })
        }
    }catch{$errors.Add([pscustomobject]@{scope='Mapped network drives';error=$_.Exception.Message})}
    [pscustomobject]@{volumes=@($volumes.ToArray() | Sort-Object {($_.mountPaths -join ',')});errors=@($errors.ToArray());status=if($errors.Count){'Partial'}elseif(-not $volumes.Count){'Not Assessed'}else{'Collected'}}
}

function Invoke-BeaconLocalCollection {
    [CmdletBinding()]
    param([ValidateRange(3,900)][int]$ObservationSeconds=5,[scriptblock]$SqlObserver)
    # Keep this helper inside the collector so serialized cluster-member collection
    # runs the same checks on that member, rather than on the portal computer.
    function Read-BeaconPendingReboot {
        param([scriptblock]$ReadIndicator)
        if(-not $ReadIndicator){
            $ReadIndicator={
                param($Indicator)
                $base=$null;$key=$null
                try{
                    $view=if([Environment]::Is64BitOperatingSystem){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Default}
                    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
                    $key=$base.OpenSubKey($Indicator.key,$false)
                    if(-not $key){return $false}
                    if(-not $Indicator.valueName){return $true}
                    if($key.GetValueNames() -notcontains $Indicator.valueName){return $false}
                    $data=$key.GetValue($Indicator.valueName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    return @($data | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_)}).Count -gt 0
                }finally{if($key){$key.Dispose()};if($base){$base.Dispose()}}
            }
        }
        $definitions=@(
            @{name='Component Based Servicing';key='SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending';valueName=$null},
            @{name='Windows Update';key='SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired';valueName=$null},
            @{name='Pending file rename operations';key='SYSTEM\CurrentControlSet\Control\Session Manager';valueName='PendingFileRenameOperations'},
            @{name='Additional pending file rename operations';key='SYSTEM\CurrentControlSet\Control\Session Manager';valueName='PendingFileRenameOperations2'}
        )
        $indicators=@(foreach($definition in $definitions){
            $pending=$null;$errorText=$null
            try{$pending=& $ReadIndicator $definition;if($pending -isnot [bool]){throw 'The reboot indicator did not return a valid result.'}}catch{$pending=$null;$errorText=$_.Exception.Message}
            [pscustomobject]@{name=$definition.name;registryPath=('HKLM\'+$definition.key);valueName=$definition.valueName;pending=$pending;status=if($errorText){'Not Assessed'}elseif($pending){'Detected'}else{'Not detected'};error=$errorText}
        })
        $reasons=@($indicators | Where-Object {$_.pending -eq $true} | ForEach-Object {$_.name})
        $unreadable=@($indicators | Where-Object {$_.error})
        [pscustomobject]@{
            checkedAtUtc=[datetime]::UtcNow.ToString('o');pending=if($reasons.Count){$true}elseif($unreadable.Count){$null}else{$false}
            status=if($reasons.Count){'Warning'}elseif($unreadable.Count){'Not Assessed'}else{'Healthy'}
            coverage=if($unreadable.Count){'Partial'}else{'Collected'};reasons=$reasons;indicators=$indicators
            scope='Windows servicing, Windows Update and pending file rename registry indicators. Other products may use additional signals. File rename entries can remain stale; review the evidence before scheduling a restart.'
        }
    }
    # Local CIM only. No target parameter, remote sessions, probes or generated load.
    $started = [DateTime]::UtcNow
    $errors = New-Object Collections.Generic.List[object]
    $reboot=Read-BeaconPendingReboot
    foreach($indicator in $reboot.indicators){if($indicator.error){$errors.Add([pscustomobject]@{scope=('Pending reboot / '+$indicator.name);error=$indicator.error})}}
    function Read-LocalCim([string]$Class, [string]$Filter) {
        try {
            Get-CimInstance -Namespace root/cimv2 -ClassName $Class -Filter $Filter -OperationTimeoutSec 10 -ErrorAction Stop
        } catch { $errors.Add([pscustomobject]@{scope=$Class;error=$_.Exception.Message}); return $null }
    }
    $drive = [string]$env:SystemDrive
    $disk = Read-LocalCim 'Win32_LogicalDisk' "DeviceID='$drive' AND DriveType=3"
    $capacity=Read-BeaconVolumes
    foreach($issue in $capacity.errors){$errors.Add($issue)}
    $samples = New-Object Collections.Generic.List[object]
    $sampleTimer=[Diagnostics.Stopwatch]::StartNew(); $i=0; do {
        if ($i -gt 0) { Start-Sleep -Seconds ([math]::Min(5,[math]::Max(1,$ObservationSeconds-$sampleTimer.Elapsed.TotalSeconds))) }
        $cpu = Read-LocalCim 'Win32_PerfRawData_PerfOS_Processor' "Name='_Total'"
        $storage = Read-LocalCim 'Win32_PerfRawData_PerfDisk_LogicalDisk' "Name='$drive'"
        $os = Read-LocalCim 'Win32_OperatingSystem' "Primary=True"
        if($SqlObserver){ & $SqlObserver }; $i++
        $samples.Add([pscustomobject]@{
            timestamp=[DateTime]::UtcNow.ToString('o')
            cpuIdleTicks=if($cpu){[double]$cpu.PercentProcessorTime}else{$null}
            cpuTimestamp=if($cpu){[double]$cpu.Timestamp_Sys100NS}else{$null}
            diskTicks=if($storage){[double]$storage.AvgDisksecPerTransfer}else{$null}
            diskTransfers=if($storage){[double]$storage.AvgDisksecPerTransfer_Base}else{$null}
            diskFrequency=if($storage){[double]$storage.Frequency_PerfTime}else{$null}
            totalMemoryKB=if($os){[double]$os.TotalVisibleMemorySize}else{$null}
            freeMemoryKB=if($os){[double]$os.FreePhysicalMemory}else{$null}
        })
        if($samples.Count -eq 1){$sampleTimer.Restart()}
    } while($sampleTimer.Elapsed.TotalSeconds -lt $ObservationSeconds -or $samples.Count -lt 3)
    $cpuValues = New-Object Collections.Generic.List[double]
    $diskSeconds=0.0; $transfers=0.0
    for ($i=1; $i -lt $samples.Count; $i++) {
        $a=$samples[$i-1]; $b=$samples[$i]
        if ($null -ne $a.cpuIdleTicks -and $null -ne $b.cpuIdleTicks -and $b.cpuTimestamp -gt $a.cpuTimestamp) {
            $idle=$b.cpuIdleTicks-$a.cpuIdleTicks; $elapsed=$b.cpuTimestamp-$a.cpuTimestamp
            if($idle -ge 0 -and $idle -le $elapsed) { $cpuValues.Add(100.0*(1.0-$idle/$elapsed)) }
        }
        if($null -ne $a.diskTicks -and $null -ne $b.diskTicks -and $b.diskFrequency -gt 0) {
            $count=$b.diskTransfers-$a.diskTransfers; $ticks=$b.diskTicks-$a.diskTicks
            if($count -gt 0 -and $ticks -ge 0) { $diskSeconds += $ticks/$b.diskFrequency; $transfers += $count }
        }
    }
    $memory=@($samples | Where-Object { $null -ne $_.freeMemoryKB -and $_.totalMemoryKB -gt 0 })
    $completed=[DateTime]::UtcNow
    $seconds=([DateTime]::Parse($samples[$samples.Count-1].timestamp)-[DateTime]::Parse($samples[0].timestamp)).TotalSeconds
    $m=[ordered]@{
        cpu=if($cpuValues.Count -eq ($samples.Count-1)){[Math]::Round(($cpuValues | Measure-Object -Average).Average,2)}else{$null}
        memoryUsed=if($memory.Count -eq $samples.Count){[Math]::Round(($memory | ForEach-Object {100*(1-$_.freeMemoryKB/$_.totalMemoryKB)} | Measure-Object -Average).Average,2)}else{$null}
        availableGB=if($memory.Count -eq $samples.Count){[Math]::Round(($memory | Measure-Object freeMemoryKB -Average).Average/1MB,2)}else{$null}
        totalMemoryGB=if($memory.Count){[Math]::Round($memory[0].totalMemoryKB/1MB,2)}else{$null}
        diskFree=if($disk -and $disk.Size -gt 0){[Math]::Round(100*$disk.FreeSpace/$disk.Size,2)}else{$null}
        diskTotalGB=if($disk -and $disk.Size -gt 0){[Math]::Round($disk.Size/1GB,2)}else{$null}
        volumes=@($capacity.volumes);volumeCapacityStatus=$capacity.status
        pendingReboot=$reboot
        storageMs=if($transfers -gt 0 -and @($samples | Where-Object {$null -eq $_.diskTicks}).Count -eq 0){[Math]::Round(1000*$diskSeconds/$transfers,3)}else{$null}
        sampledMinutes=$seconds/60; observationSeconds=[Math]::Round($seconds,3); localSnapshot=$true; diskLabel=$drive
        sqlTotalMB=$null; sqlTargetMB=$null; grants=$null; pressureMinutes=$null; uptimeMinutes=$null
    }
    if($null -eq $m.cpu){$errors.Add([pscustomobject]@{scope='CPU';error='Complete valid CPU counter intervals were not available.'})}
    if($null -eq $m.storageMs){$errors.Add([pscustomobject]@{scope='Storage latency';error='No usable disk transfer interval; an idle disk has no measured latency.'})}
    [pscustomobject]@{
        Target=[Environment]::MachineName; Platform='Windows'; Mode='local'; StartedAt=$started.ToString('o'); CompletedAt=$completed.ToString('o')
        ExecutionSource=[Environment]::MachineName; Measurements=[pscustomobject]$m; Samples=@($samples.ToArray()); Errors=@($errors.ToArray())
        Coverage='Timestamped local samples; CPU and system-volume latency use counter deltas. Memory is the sample mean. Capacity covers mounted volumes, including folder mounts and network drives visible to this execution identity. Unmounted partitions are excluded. Short observations do not establish sustained conditions.'
    }
}
Export-ModuleMember -Function Invoke-BeaconLocalCollection
