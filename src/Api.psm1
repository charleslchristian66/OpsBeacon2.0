function Assert-BeaconRequest($Request) {
    $hostHeader=[string]$Request.Headers['Host'];$origin=[string]$Request.Headers['Origin']
    if($hostHeader -notmatch '^(127\.0\.0\.1|localhost):[0-9]{1,5}$' -or $Request.Headers['X-OpsBeacon-Live'] -ne '1' -or ($origin -and $origin -ne "http://$hostHeader")) {throw 'A same-origin Ops Beacon request is required.'}
}
function ConvertTo-BeaconRequest($Data,$Root,[string]$Action) {
    $config=Get-Content -LiteralPath (Join-Path $Root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $target=[string]$Data.target
    if($target -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,252}$'){throw 'Enter a Windows computer name, FQDN or IPv4 address.'}
    if($Data.execution -notin @('local','remote')){throw 'Select local collection or Windows remoting.'}
    if($Data.execution -eq 'local' -and $target -ine [Environment]::MachineName){throw 'Local collection must target this computer by its displayed computer name.'}
    $options=[ordered]@{target=$target;os='Windows';profile='General Purpose';sql=$false;cluster=$false;events=$false;connectivity=$false;execution=[string]$Data.execution;sqlInstance='Auto';observationSeconds=5}
    foreach($name in @('sql','cluster','events','connectivity')){if($null -ne $Data.$name -and $Data.$name -isnot [bool]){throw "Invalid capability: $name"};$options[$name]=[bool]$Data.$name}
    if($Action -eq 'assess'){
        $profile=[string]$Data.profile
        if(-not $profile){$profile='General Purpose Server'}
        if($profile -notin @('General Purpose Server','Database Server','Cluster Node')){throw 'Select a supported server profile.'}
        $options.profile=$profile
        $seconds=0;if(-not [int]::TryParse([string]$Data.observationSeconds,[ref]$seconds) -or $seconds -lt 3 -or $seconds -gt 900){throw 'Observation duration must be 3 to 900 seconds.'};$options.observationSeconds=$seconds
        $instance=[string]$Data.sqlInstance;if($instance -and $instance -notmatch '^[a-zA-Z0-9_$-]{1,64}$'){throw 'SQL instance must be Auto, MSSQLSERVER or a local instance name.'};if($instance){$options.sqlInstance=$instance}
    }
    $destinations=@()
    if(@($Data.destinations).Count -gt 20){throw 'At most 20 destinations may be inspected.'}
    foreach($d in @($Data.destinations)){
        if($null -eq $d){continue};$port=0
        if([string]$d.host -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,252}$' -or -not [int]::TryParse([string]$d.port,[ref]$port) -or $port -lt 1 -or $port -gt 65535 -or $d.protocol -notin @('http','https')){throw 'Each destination needs a hostname/IP, port 1-65535 and http or https protocol.'}
        $destinations+=@{host=[string]$d.host;port=$port;protocol=[string]$d.protocol}
    }
    $query=$null
    if($Action -eq 'events'){
        $begin=[datetime]::MinValue;$end=[datetime]::MinValue
        if(-not [datetime]::TryParse([string]$Data.start,[ref]$begin) -or -not [datetime]::TryParse([string]$Data.end,[ref]$end)){throw 'Invalid event time range.'}
        if($end -le $begin -or ($end-$begin).TotalHours -gt 168){throw 'Event queries must cover more than zero and at most 168 hours.'}
        $logs=@($Data.logs);$allowed=@('System','Application','Microsoft-Windows-FailoverClustering/Operational')
        if(-not $logs.Count -or $logs.Count -gt 3 -or @($logs | Where-Object {$_ -notin $allowed}).Count){throw 'Choose supported Windows event logs.'}
        $eventId=$null;if([string]$Data.eventId -ne ''){$number=0;if(-not [int]::TryParse([string]$Data.eventId,[ref]$number) -or $number -lt 0 -or $number -gt 65535){throw 'Event ID must be 0-65535.'};$eventId=$number}
        $provider=[string]$Data.provider
        if($provider.Length -gt 256){throw 'Event source must be at most 256 characters.'}
        if($null -ne $Data.errorsOnly -and $Data.errorsOnly -isnot [bool]){throw 'Invalid error filter.'}
        $query=@{start=$begin.ToUniversalTime().ToString('o');end=$end.ToUniversalTime().ToString('o');logs=$logs;eventId=$eventId;provider=$provider;errorsOnly=[bool]$Data.errorsOnly;maxEvents=[int]$config.events.maxEvents}
    }
    return @{action=$Action;options=$options;destinations=$destinations;query=$query;rules=$config.rules;connectivity=$config.connectivity;events=$config.events}
}
function New-BeaconJob($Data,$Root,[string]$Action) {
    $request=ConvertTo-BeaconRequest $Data $Root $Action
    Import-Module (Join-Path $Root 'src/JobStatus.psm1') -Force
    $folder=Join-Path $Root 'jobs';New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $id=[guid]::NewGuid().ToString()
    $submittedAt=[datetime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $folder "$id.request.json"),($request | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    $statusPath=Join-Path $folder "$id.status.json"
    $queued=@{id=$id;action=$Action;target=$request.options.target;state='Queued';submittedAt=$submittedAt;startedAt=$null;completedAt=$null;pollUrl="/api/jobs/$id"}
    Write-BeaconJobStatus -Path $statusPath -Value $queued
    try{
        $runner=Join-Path $Root 'src/Invoke-Job.ps1'
        # Match the original Ops Beacon: acknowledge Queued, dispatch a Start-Job
        # immediately, and poll persisted status. No waiting FIFO or two-job gate.
        $null=Start-Job -Name "OpsBeacon-$id" -ScriptBlock {param($Runner,$Id) & $Runner -Id $Id} -ArgumentList $runner,$id -ErrorAction Stop
        return $queued
    }catch{
        $queued.state='Failed';$queued.Error=$_.Exception.Message;$queued.completedAt=[datetime]::UtcNow.ToString('o')
        Write-BeaconJobStatus -Path $statusPath -Value $queued
        $_.Exception.Data['HttpStatusCode']=503
        throw
    }
}
Export-ModuleMember -Function Assert-BeaconRequest,ConvertTo-BeaconRequest,New-BeaconJob
