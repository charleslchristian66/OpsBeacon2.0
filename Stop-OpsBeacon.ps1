[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateRange(0,65535)][int]$Port=0)
$ErrorActionPreference='Stop'

function Test-BeaconLauncher($Process,[string]$Launcher,$Registration){
    if(-not $Process -or $Process.Name -ine 'powershell.exe' -or -not $Process.CommandLine){return $false}
    $arguments=@([regex]::Matches($Process.CommandLine,'"[^"]*"|\S+') | ForEach-Object {$_.Value.Trim('"')})
    for($index=1;$index -lt $arguments.Count;$index++){
        $argument=$arguments[$index]
        if($argument -ieq '-File'){
            if($index+1 -ge $arguments.Count){return $false}
            $file=$arguments[$index+1]
            if([IO.Path]::IsPathRooted($file)){return [IO.Path]::GetFullPath($file) -ieq $Launcher}
            # A relative -File needs this deployment's launch record to establish its root.
            if(-not $Registration -or $Registration.processId -ne $Process.ProcessId -or $Registration.scriptPath -ine $Launcher){return $false}
            $difference=([datetime]::Parse($Registration.startedUtc).ToUniversalTime()-$Process.CreationDate.ToUniversalTime()).TotalMilliseconds
            return [math]::Abs($difference) -lt 1 -and [IO.Path]::GetFullPath((Join-Path (Split-Path $Launcher -Parent) $file)) -ieq $Launcher
        }
        if($argument -in @('-ExecutionPolicy','-WindowStyle')){$index++;continue}
        if($argument -notin @('-NoProfile','-NoLogo','-NonInteractive','-NoExit','-Sta','-Mta')){return $false}
    }
    return $false
}

function Get-BeaconDescendants($RootProcess,$Processes){
    $pending=New-Object 'Collections.Generic.Queue[uint32]';$pending.Enqueue([uint32]$RootProcess.ProcessId)
    $seen=@{};$seen[[uint32]$RootProcess.ProcessId]=$true
    while($pending.Count){
        $parent=$pending.Dequeue()
        foreach($child in @($Processes | Where-Object ParentProcessId -eq $parent)){
            if($seen.ContainsKey([uint32]$child.ProcessId) -or $child.CreationDate -lt $RootProcess.CreationDate){continue}
            $seen[[uint32]$child.ProcessId]=$true;$pending.Enqueue([uint32]$child.ProcessId)
            if($child.Name -ieq 'powershell.exe'){$child}
        }
    }
}

function Stop-BeaconVerifiedProcess($Snapshot){
    $current=Get-CimInstance Win32_Process -Filter "ProcessId=$([uint32]$Snapshot.ProcessId)"
    if(-not $current){return}
    if($current.CreationDate -ne $Snapshot.CreationDate){throw "Process ID $($Snapshot.ProcessId) was reused; refusing to stop it."}
    $process=Get-Process -Id $current.ProcessId -ErrorAction SilentlyContinue
    if($process){
        if([math]::Abs(($process.StartTime.ToUniversalTime()-$Snapshot.CreationDate.ToUniversalTime()).TotalMilliseconds) -ge 1){throw 'Process identity changed; refusing to stop it.'}
        Stop-Process -InputObject $process -ErrorAction Stop
    }
}

if($Port -eq 0){$Port=[int](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json).port}
if($Port -lt 1024){throw 'Use a port between 1024 and 65535.'}
$listeners=@(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
if(-not $listeners.Count){Write-Host "Ops Beacon is already stopped on port $Port; no listener was found.";return}
$launcher=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Start-OpsBeacon.ps1'))
$servers=@()
foreach($ownerId in @($listeners.OwningProcess | Sort-Object -Unique)){
    $owner=Get-CimInstance Win32_Process -Filter "ProcessId=$([uint32]$ownerId)"
    $registration=$null;$record=Join-Path $PSScriptRoot "jobs/launcher-$ownerId.json"
    if(Test-Path -LiteralPath $record){try{$registration=Get-Content -LiteralPath $record -Raw -Encoding UTF8 | ConvertFrom-Json}catch{}}
    if($ownerId -eq $PID -or -not (Test-BeaconLauncher $owner $launcher $registration)){
        throw "Port $Port belongs to process $ownerId, which could not be verified as this deployment's dedicated Ops Beacon launcher. Nothing was stopped. Use Start-OpsBeacon.cmd to launch; if it runs elevated, run this stop script as administrator."
    }
    $servers+=$owner
}
# Validate every port owner before stopping anything; never stop by name or by port alone.
$processes=@(Get-CimInstance Win32_Process)
$workers=@($servers | ForEach-Object {Get-BeaconDescendants $_ $processes})
$workerIds=@($workers.ProcessId)
$performed=$false
foreach($server in $servers){
    if($PSCmdlet.ShouldProcess("Ops Beacon PID $($server.ProcessId), port $Port, $launcher",'Stop server and its assessment workers')){
        $performed=$true
        Stop-BeaconVerifiedProcess $server
        foreach($worker in $workers){Stop-BeaconVerifiedProcess $worker}
    }
}
if(-not $performed){return}
$deadline=[datetime]::UtcNow.AddSeconds(10)
while(@(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).Count){
    if([datetime]::UtcNow -ge $deadline){throw "Port $Port still has a listener. Review its owner; no unrelated process was stopped."}
    Start-Sleep -Milliseconds 250
}
if($workerIds.Count){
    Import-Module (Join-Path $PSScriptRoot 'src/JobStatus.psm1') -Force
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'jobs') -Filter '*.status.json' -File -ErrorAction SilentlyContinue)){
        try{
            $status=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if($status.state -eq 'Running' -and $status.pid -in $workerIds){
                $status.state='Failed';$status.completedAt=[datetime]::UtcNow.ToString('o')
                $status | Add-Member -NotePropertyName Error -NotePropertyValue 'Assessment interrupted because Ops Beacon was stopped.' -Force
                Write-BeaconJobStatus -Path $file.FullName -Value $status
            }
        }catch{Write-Warning "Port released, but could not update interrupted-job status: $($_.Exception.Message)"}
    }
}
Write-Host "Ops Beacon stopped. Port $Port is released. Saved reports are preserved."
