[CmdletBinding()]
param(
    [ValidateRange(0,65535)][int]$Port=0,
    [ValidateRange(1,256)][int]$WorkerThreads=8,
    [ValidateRange(1,86400)][int]$RequestTimeoutSeconds=600
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -lt 1){throw 'Launch with Windows PowerShell 5.1 (powershell.exe).'}
if($Port -eq 0){$Port=[int](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json).port}
if($Port -lt 1024){throw 'Use a port between 1024 and 65535.'}
Import-Module (Join-Path $PSScriptRoot 'vendor/Pode/2.13.4/Pode.psd1') -ErrorAction Stop
$probe=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$Port)
try{$probe.Start()}catch{throw "Port $Port is already in use. Choose -Port with a free port; no process was stopped."}finally{$probe.Stop()}
$script:BeaconPort=$Port
$serverConfig=Join-Path $PSScriptRoot 'server.psd1'
if($RequestTimeoutSeconds -ne 600){
    # Pode 2.13 reads the listener timeout from Server.Request in its data file.
    $runtime=Join-Path $PSScriptRoot 'jobs'
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null
    $serverConfig=Join-Path $runtime "server-$PID.psd1"
    [IO.File]::WriteAllText($serverConfig,"@{ Server = @{ Request = @{ Timeout = $RequestTimeoutSeconds } } }",(New-Object Text.UTF8Encoding($false)))
}
Write-Host "Ops Beacon 2.0 | LIVE read-only Windows assessments | http://127.0.0.1:$Port | Ctrl+C to stop"
Write-Host "Web worker threads: $WorkerThreads | Request timeout: $RequestTimeoutSeconds seconds | Background jobs: original Ops Beacon dispatch"
$runtime=Join-Path $PSScriptRoot 'jobs';New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$launchRecord=Join-Path $runtime "launcher-$PID.json"
$launchIdentity=@{processId=$PID;scriptPath=$PSCommandPath;port=$Port;startedUtc=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o')}
[IO.File]::WriteAllText($launchRecord,($launchIdentity | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
try{
Start-PodeServer -RootPath $PSScriptRoot -Threads $WorkerThreads -ConfigFile $serverConfig -ScriptBlock {
    Add-PodeEndpoint -Address '127.0.0.1' -Port $script:BeaconPort -Protocol Http
    Add-PodeStaticRoute -Path '/assets' -Source './public/assets'
    Add-PodeRoute -Method Get -Path '/' -ScriptBlock {Write-PodeHtmlResponse -Path './public/index.html'}
    Add-PodeRoute -Method Head -Path '/' -ScriptBlock {Write-PodeTextResponse -Value '' -StatusCode 200}
    Add-PodeRoute -Method Get -Path '/api/config' -ScriptBlock {
        $config=Get-Content -LiteralPath (Join-Path (Get-PodeServerPath) 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-PodeJsonResponse -Value @{config=$config;target=[Environment]::MachineName;identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;mode='live';runtime=@{workerThreads=$PodeContext.Threads.General;requestTimeoutSeconds=$PodeContext.Server.Request.Timeout;probeWorkers=$config.connectivity.maxConcurrent;jobEngine='Start-Job';dispatch='Immediate';waitingQueue=$false;maxConcurrentJobs=$null}} -Depth 20
    }
    Add-PodeRoute -Method Post -Path '/api/jobs/:action' -ScriptBlock {
        try{
            Import-Module (Join-Path (Get-PodeServerPath) 'src/Api.psm1') -Force
            Assert-BeaconRequest $WebEvent.Request
            $action=[string]$WebEvent.Parameters.action;if($action -notin @('assess','events')){throw 'Unknown collection action.'}
            if($WebEvent.Request.ContentLength -gt 65536){throw 'Collection request exceeds 64 KB.'}
            $data=$WebEvent.Data;$root=Get-PodeServerPath
            $job=Lock-PodeObject -Object $PodeContext.Threading.Lockables.Global -Return -ScriptBlock {New-BeaconJob $data $root $action}
            Write-PodeJsonResponse -StatusCode 202 -Value $job
        }catch{
            $code=400;if($_.Exception.Data['HttpStatusCode'] -eq 503){$code=503}
            Write-PodeJsonResponse -StatusCode $code -Value @{Error=$_.Exception.Message}
        }
    }
    Add-PodeRoute -Method Get -Path '/api/jobs/:id' -ScriptBlock {
        $id=[string]$WebEvent.Parameters.id
        if($id -notmatch '^[a-f0-9-]{36}$'){Write-PodeJsonResponse -StatusCode 400 -Value @{Error='Invalid collection ID.'};return}
        $path=Join-Path (Get-PodeServerPath) "jobs/$id.status.json"
        if(-not (Test-Path -LiteralPath $path)){Write-PodeJsonResponse -StatusCode 404 -Value @{Error='Collection not found.'};return}
        $state=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-PodeJsonResponse -Value $state -Depth 75
    }
    Add-PodeRoute -Method Post -Path '/api/reports' -ScriptBlock {
        try{
            Import-Module (Join-Path (Get-PodeServerPath) 'src/Api.psm1') -Force;Assert-BeaconRequest $WebEvent.Request
            $report=$WebEvent.Data;$id=[string]$report.AssessmentId
            if($id -notmatch '^[a-f0-9-]{36}$' -or $report.Mode -ne 'live' -or $report.SchemaVersion -ne '2.0.0'){throw 'Expected a version 2 live assessment with a UUID.'}
            $json=$report | ConvertTo-Json -Depth 80;if($json.Length -gt 10000000){throw 'Report exceeds 10 MB.'}
            $folder=Join-Path (Get-PodeServerPath) 'reports';New-Item -ItemType Directory -Path $folder -Force | Out-Null
            Lock-PodeObject -Object $PodeContext.Threading.Lockables.Global -ScriptBlock {[IO.File]::WriteAllText((Join-Path $folder "$id.json"),$json,(New-Object Text.UTF8Encoding($false)))}
            Write-PodeJsonResponse -Value @{Saved=$true;Url="/assets/report.html?id=$id"}
        }catch{Write-PodeJsonResponse -StatusCode 400 -Value @{Error=$_.Exception.Message}}
    }
    Add-PodeRoute -Method Get -Path '/api/reports/:id' -ScriptBlock {
        $id=[string]$WebEvent.Parameters.id
        if($id -notmatch '^[a-f0-9-]{36}$'){Write-PodeJsonResponse -StatusCode 400 -Value @{Error='Invalid assessment ID.'};return}
        $path=Join-Path (Get-PodeServerPath) "reports/$id.json"
        if(-not (Test-Path -LiteralPath $path)){Write-PodeJsonResponse -StatusCode 404 -Value @{Error='Report not found.'};return}
        Write-PodeJsonResponse -Value (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) -Depth 80
    }
}
}finally{if(Test-Path -LiteralPath $launchRecord){Remove-Item -LiteralPath $launchRecord -Force}}
