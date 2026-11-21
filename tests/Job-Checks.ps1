[CmdletBinding()]
param([string]$BaseUrl='http://127.0.0.1:8080')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$checks=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Passed){$checks.Add(@{name=$Name;passed=$Passed});if(-not $Passed){throw "FAILED: $Name"}}
$info=Invoke-RestMethod "$BaseUrl/api/config" -TimeoutSec 15
Check 'Original eight web worker threads are active' ($info.runtime.workerThreads -eq 8)
Check 'Original 600-second HTTP request timeout is active' ($info.runtime.requestTimeoutSeconds -eq 600)
Check 'Original immediate Start-Job dispatch has no two-job gate' ($info.runtime.jobEngine -eq 'Start-Job' -and $info.runtime.dispatch -eq 'Immediate' -and -not $info.runtime.waitingQueue -and $null -eq $info.runtime.maxConcurrentJobs)
$headers=@{'X-OpsBeacon-Live'='1'}
$body=@{target=$info.target;execution='local';profile='General Purpose Server';observationSeconds=10;sql=$false;cluster=$false;events=$false;connectivity=$false;destinations=@()} | ConvertTo-Json
$jobs=@()
for($index=0;$index -lt 3;$index++){
    $response=Invoke-WebRequest -UseBasicParsing "$BaseUrl/api/jobs/assess" -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 20
    $job=$response.Content | ConvertFrom-Json
    Check "Submission $index acknowledged as queued with HTTP 202" ($response.StatusCode -eq 202 -and $job.state -eq 'Queued' -and $job.submittedAt -and $job.pollUrl -eq "/api/jobs/$($job.id)")
    $jobs+=$job
}
Check 'Three independent jobs accepted with unique IDs' (@($jobs.id | Sort-Object -Unique).Count -eq 3)
$seen=@{};$maxRunning=0;$deadline=[datetime]::UtcNow.AddMinutes(3)
do{
    $states=@($jobs | ForEach-Object {Invoke-RestMethod "$BaseUrl$($_.pollUrl)" -TimeoutSec 15})
    foreach($state in $states){
        if($state.state -eq 'Failed'){throw "Collection $($state.id) failed: $($state.Error)"}
        if($state.startedAt){$seen[$state.id]=$true}
    }
    $running=@($states | Where-Object state -eq 'Running').Count
    $maxRunning=[math]::Max($maxRunning,$running)
    if(@($states | Where-Object state -ne 'Completed').Count -eq 0){break}
    if([datetime]::UtcNow -gt $deadline){throw 'Concurrent collection checks exceeded three minutes.'}
    Start-Sleep -Milliseconds 250
}while($true)
Check 'At least three collection processes ran concurrently' ($maxRunning -ge 3)
Check 'Each job records the running transition' ($seen.Count -eq 3)
Check 'All jobs completed with distinct worker process IDs' (@($states | Where-Object state -eq 'Completed').Count -eq 3 -and @($states.pid | Sort-Object -Unique).Count -eq 3)
Check 'Job submission/start/completion timestamps retained' (@($states | Where-Object {-not $_.submittedAt -or -not $_.startedAt -or -not $_.completedAt -or [datetime]::Parse($_.submittedAt).ToUniversalTime() -gt [datetime]::Parse($_.startedAt).ToUniversalTime() -or [datetime]::Parse($_.startedAt).ToUniversalTime() -gt [datetime]::Parse($_.completedAt).ToUniversalTime()}).Count -eq 0)
Check 'Concurrent jobs retain real local source and separate options' (@($states | Where-Object {$_.result.ExecutionSource -ne $info.target -or $_.options.profile -ne 'General Purpose Server'}).Count -eq 0)

# Exercise a worker failure in an isolated folder; never change a real request.
$scratch=Join-Path $root "jobs/queue-check-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path (Join-Path $scratch 'src'),(Join-Path $scratch 'jobs') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'config.json') -Destination (Join-Path $scratch 'config.json')
foreach($name in @('Invoke-Job.ps1','JobStatus.psm1','LocalCollector.psm1','TargetWorker.ps1')){Copy-Item -LiteralPath (Join-Path $root "src/$name") -Destination (Join-Path $scratch "src/$name")}
$failedId=[guid]::NewGuid().ToString();$submitted=[datetime]::UtcNow.ToString('o')
@{action='assess';options=@{execution='local';target='DELIBERATE-IDENTITY-MISMATCH'}} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $scratch "jobs/$failedId.request.json") -Encoding UTF8
@{state='Queued';submittedAt=$submitted} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $scratch "jobs/$failedId.status.json") -Encoding UTF8
& (Join-Path $scratch 'src/Invoke-Job.ps1') -Id $failedId
$failed=Get-Content -LiteralPath (Join-Path $scratch "jobs/$failedId.status.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Check 'Worker failure persists a terminal error without local fallback' ($failed.state -eq 'Failed' -and $failed.Error -like '*identity mismatch*' -and -not $failed.portalFallbackAllowed -and $null -eq $failed.actualSource)
Check 'Failed job retains lifecycle timestamps and request ID' ($failed.id -eq $failedId -and $failed.submittedAt -eq $submitted -and $failed.startedAt -and $failed.completedAt)

# Inject only the dispatch dependency in an isolated module scope to verify a
# launcher failure is reported, without killing or changing any real worker.
Import-Module (Join-Path $root 'src/Api.psm1') -Force
$api=Get-Module Api
$launchFailure=& $api {
    param($Data,$Root)
    function Start-Job {throw 'Deliberate launch failure for verification.'}
    try{New-BeaconJob $Data $Root 'assess'}catch{[pscustomobject]@{code=$_.Exception.Data['HttpStatusCode'];message=$_.Exception.Message}}
} (@{target=$info.target;execution='local';observationSeconds=3;destinations=@()}) $scratch
Check 'Launch failure is marked service unavailable' ($launchFailure.code -eq 503 -and $launchFailure.message -like '*Deliberate launch failure*')
$dispatchFailed=@(Get-ChildItem (Join-Path $scratch 'jobs') -Filter '*.status.json' | Where-Object BaseName -ne "$failedId.status" | ForEach-Object {Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json})
Check 'Launch failure persists Failed instead of a stranded Queued job' ($dispatchFailed.Count -eq 1 -and $dispatchFailed[0].state -eq 'Failed' -and $dispatchFailed[0].completedAt)
$checks | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'job-results.json') -Encoding UTF8
$checks | ForEach-Object {[pscustomobject]$_} | Format-Table -AutoSize
