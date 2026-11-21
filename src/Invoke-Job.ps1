param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9-]{36}$')][string]$Id)
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;$folder=Join-Path $root 'jobs'
Import-Module (Join-Path $PSScriptRoot 'JobStatus.psm1') -Force
$statusPath=Join-Path $folder "$Id.status.json"
$submittedAt=$null;$startedAt=[datetime]::UtcNow.ToString('o')
try{
    $submittedAt=(Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json).submittedAt
    $request=Get-Content -LiteralPath (Join-Path $folder "$Id.request.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-BeaconJobStatus -Path $statusPath -Value @{id=$Id;action=$request.action;target=$request.options.target;state='Running';submittedAt=$submittedAt;startedAt=$startedAt;completedAt=$null;pid=$PID}
    $general=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'LocalCollector.psm1') -Raw -Encoding UTF8
    $general=$general -replace '(?m)^Export-ModuleMember.*$',''
    $worker=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'TargetWorker.ps1') -Raw -Encoding UTF8
    $worker=$worker -replace '^param\(\$Request\)\s*',''
    $block=[scriptblock]::Create("param(`$Request)`n$general`n$worker")
    if($request.options.execution -eq 'local'){
        if($request.options.target -ine [Environment]::MachineName){throw 'Local target identity mismatch.'}
        $result=& $block $request
    }else{
        $session=$null
        try{
            # Default Windows Negotiate authentication; never change TrustedHosts or use alternate credentials.
            $session=New-PSSession -ComputerName $request.options.target -SessionOption (New-PSSessionOption -OpenTimeout 5000 -OperationTimeout 1200000) -ErrorAction Stop
            $result=Invoke-Command -Session $session -ScriptBlock $block -ArgumentList $request -ErrorAction Stop
        }finally{if($session){Remove-PSSession $session}}
    }
    $envelope=@{state='Completed';result=$result;options=$request.options}
}catch{$envelope=@{state='Failed';Error=$_.Exception.Message;requestedSource=$request.options.target;actualSource=$null;portalFallbackAllowed=$false}}
$envelope.id=$Id;$envelope.action=$request.action;$envelope.target=$request.options.target
$envelope.submittedAt=$submittedAt;$envelope.startedAt=$startedAt;$envelope.completedAt=[datetime]::UtcNow.ToString('o');$envelope.pid=$PID
Write-BeaconJobStatus -Path $statusPath -Value $envelope
