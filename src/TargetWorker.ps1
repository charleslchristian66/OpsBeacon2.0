param($Request)
$ErrorActionPreference='Stop'
$started=[DateTime]::UtcNow
$source=[Environment]::MachineName
$issues=New-Object 'Collections.Generic.List[object]'
function Add-Issue([string]$Scope,[string]$Message) { $issues.Add([pscustomobject]@{scope=$Scope;error=$Message}) }

function Read-BeaconTimeZone {
    param([datetime]$StartUtc,[datetime]$EndUtc,[TimeZoneInfo]$Zone=[TimeZoneInfo]::Local)
    # Capture the target's actual Windows rules, including a locally disabled DST setting.
    # Browsers cannot directly use Windows zone IDs. UTC offset periods avoid host/browser assumptions.
    $now=[datetime]::UtcNow
    $first=[datetime]::SpecifyKind((New-Object datetime ($now.Year-1),1,1),[DateTimeKind]::Utc)
    $last=$first.AddYears(3)
    $ranges=@(@{start=$first;end=$last})
    if($StartUtc -and $EndUtc -and ($StartUtc -lt $first -or $EndUtc -ge $last)){
        $ranges+=@{start=$StartUtc.ToUniversalTime().Date;end=$EndUtc.ToUniversalTime().Date.AddDays(1)}
    }
    $periods=New-Object 'Collections.Generic.List[object]'
    foreach($range in $ranges){
        $cursor=$range.start;$periodStart=$cursor
        $offset=$Zone.GetUtcOffset($cursor).TotalMinutes;$daylight=$Zone.IsDaylightSavingTime($cursor)
        while($cursor -lt $range.end){
            $next=$cursor.AddHours(6);if($next -gt $range.end){$next=$range.end}
            $nextOffset=$Zone.GetUtcOffset($next).TotalMinutes;$nextDaylight=$Zone.IsDaylightSavingTime($next)
            if($nextOffset -ne $offset -or $nextDaylight -ne $daylight){
                $low=$cursor;$high=$next
                while(($high-$low).TotalMilliseconds -gt 1){
                    $middle=$low.AddMilliseconds([math]::Floor(($high-$low).TotalMilliseconds/2))
                    if($Zone.GetUtcOffset($middle).TotalMinutes -eq $offset -and $Zone.IsDaylightSavingTime($middle) -eq $daylight){$low=$middle}else{$high=$middle}
                }
                $periods.Add([pscustomobject]@{startUtc=$periodStart.ToString('o');endUtc=$high.ToString('o');offsetMinutes=$offset;daylight=$daylight})
                $periodStart=$high;$cursor=$high;$offset=$Zone.GetUtcOffset($high).TotalMinutes;$daylight=$Zone.IsDaylightSavingTime($high)
            }else{$cursor=$next}
        }
        $periods.Add([pscustomobject]@{startUtc=$periodStart.ToString('o');endUtc=$range.end.ToString('o');offsetMinutes=$offset;daylight=$daylight})
    }
    [pscustomobject]@{id=$Zone.Id;displayName=$Zone.DisplayName;standardName=$Zone.StandardName;daylightName=$Zone.DaylightName;supportsDaylightSavingTime=$Zone.SupportsDaylightSavingTime;capturedAt=$now.ToString('o');source=$source;periods=@($periods.ToArray())}
}

function Read-BeaconEvents($Query) {
    $items=New-Object 'Collections.Generic.List[object]'
    $coverage=New-Object 'Collections.Generic.List[object]'
    $begin=[datetime]::Parse($Query.start).ToUniversalTime(); $end=[datetime]::Parse($Query.end).ToUniversalTime()
    $limit=[int]$Query.maxEvents; $truncated=$false
    foreach($log in @($Query.logs)) {
        # Windows PowerShell 5.1 Get-WinEvent expects local DateTimes here; keep report boundaries in UTC.
        $filter=@{LogName=[string]$log;StartTime=$begin.ToLocalTime();EndTime=$end.ToLocalTime()}
        if($null -ne $Query.eventId -and [string]$Query.eventId -ne '') { $filter.Id=[int]$Query.eventId }
        if($Query.errorsOnly){$filter.Level=@(1,2)}
        try {
            # Confirm the log exists/access succeeds; a missing log is not an empty healthy log.
            $null=Get-WinEvent -ListLog $log -ErrorAction Stop
            $records=@(); $eventErrors=@()
            if($Query.provider){
                # FilterHashtable.ProviderName resolves installed publisher metadata first.
                # Historical/classic records can outlive that registration; query their stored XML instead.
                $provider=[string]$Query.provider
                $quote=if($provider.Contains("'")){'"'}else{"'"}
                if($provider.Contains("'") -and $provider.Contains('"')){
                    # Windows Event Log's XPath subset cannot quote a name containing both delimiters.
                    # Stream exact matches before applying the result cap so unrelated sources cannot hide them.
                    $records=@(Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue -ErrorVariable eventErrors | Where-Object ProviderName -EQ $provider | Select-Object -First ($limit+1))
                }else{
                    $conditions=@("Provider[@Name=$quote$provider$quote]","TimeCreated[@SystemTime >= '$($begin.ToString('o'))' and @SystemTime <= '$($end.ToString('o'))']")
                    if($filter.ContainsKey('Id')){$conditions+="EventID=$($filter.Id)"}
                    if($Query.errorsOnly){$conditions+='(Level=1 or Level=2)'}
                    $xpath='*[System['+($conditions -join ' and ')+']]'
                    $records=@(Get-WinEvent -LogName $log -FilterXPath $xpath -MaxEvents ($limit+1) -ErrorAction SilentlyContinue -ErrorVariable eventErrors)
                }
            }else{
                $records=@(Get-WinEvent -FilterHashtable $filter -MaxEvents ($limit+1) -ErrorAction SilentlyContinue -ErrorVariable eventErrors)
            }
            $realErrors=@($eventErrors | Where-Object {$_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*'})
            if($realErrors.Count) { throw $realErrors[0] }
            if($records.Count -gt $limit){$truncated=$true}
            foreach($e in @($records | Select-Object -First $limit)) {
                $message='';try{$message=[string]$e.Message}catch{$message='Event message could not be formatted.'}
                if([string]::IsNullOrWhiteSpace($message)){
                    $stored=@($e.Properties | ForEach-Object {[string]$_.Value} | Where-Object {-not [string]::IsNullOrWhiteSpace($_)})
                    $message='Windows could not format the event description. Stored event data: '+$(if($stored.Count){$stored -join ' | '}else{'No additional event data was stored.'})
                }
                if($message.Length -gt 12000){$message=$message.Substring(0,12000)+' [message truncated]'}
                $severity=switch([int]$e.Level){1{'Critical'}2{'Error'}3{'Warning'}4{'Information'}5{'Verbose'}default{'Information'}}
                $items.Add([pscustomobject]@{key="$source|$log|$($e.ProviderName)|$($e.RecordId)";server=$source;log=$log;provider=$e.ProviderName;eventId=$e.Id;recordId=$e.RecordId;timestamp=$e.TimeCreated.ToUniversalTime().ToString('o');originalTimestamp=([DateTimeOffset]$e.TimeCreated).ToString('o');originalTimeZone=[TimeZoneInfo]::Local.Id;severity=$severity;message=$message;simulated=$false})
            }
            $coverage.Add([pscustomobject]@{node=$source;log=$log;status='Collected';error=$null;matchingAtLeast=$records.Count;truncated=($records.Count -gt $limit)})
        } catch { $coverage.Add([pscustomobject]@{node=$source;log=$log;status='Not Assessed';error=$_.Exception.Message}) }
    }
    $ordered=@($items.ToArray() | Sort-Object timestamp -Descending)
    if($ordered.Count -gt $limit){$truncated=$true}
    [pscustomobject]@{events=@($ordered | Select-Object -First $limit | Sort-Object timestamp,log,recordId);searches=@($coverage.ToArray());truncated=$truncated;totalMatchingAtLeast=($coverage.ToArray() | Measure-Object matchingAtLeast -Sum).Sum;start=$begin.ToString('o');end=$end.ToString('o');collectedAt=[datetime]::UtcNow.ToString('o');source=$source;targetTimeZone=(Read-BeaconTimeZone -StartUtc $begin -EndUtc $end);eventId=$Query.eventId;provider=$Query.provider;errorsOnly=[bool]$Query.errorsOnly;maxEvents=$limit}
}

function Read-BeaconErrorSummary($Query) {
    $begin=[datetime]::Parse($Query.start).ToUniversalTime();$end=[datetime]::Parse($Query.end).ToUniversalTime()
    $groups=@{};$coverage=New-Object 'Collections.Generic.List[object]';$limit=[int]$Query.summaryLimit
    foreach($log in @('System','Application')){
        $records=@();$eventErrors=@()
        try{
            $null=Get-WinEvent -ListLog $log -ErrorAction Stop
            $filter=@{LogName=$log;StartTime=$begin.ToLocalTime();EndTime=$end.ToLocalTime();Level=@(1,2)}
            $records=@(Get-WinEvent -FilterHashtable $filter -MaxEvents ($limit+1) -ErrorAction SilentlyContinue -ErrorVariable eventErrors)
            $realErrors=@($eventErrors | Where-Object {$_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*'})
            if($realErrors.Count){throw $realErrors[0]}
            foreach($e in @($records | Select-Object -First $limit)){
                $key="$log|$($e.ProviderName)|$($e.Id)";$time=$e.TimeCreated.ToUniversalTime().ToString('o')
                if(-not $groups.ContainsKey($key)){
                    $message='';try{$message=[string]$e.Message}catch{$message='Event message could not be formatted.'}
                    if($message.Length -gt 12000){$message=$message.Substring(0,12000)+' [message truncated]'}
                    $anchor=[pscustomobject]@{key="$source|$log|$($e.ProviderName)|$($e.RecordId)";server=$source;log=$log;provider=$e.ProviderName;eventId=$e.Id;recordId=$e.RecordId;timestamp=$time;originalTimestamp=([DateTimeOffset]$e.TimeCreated).ToString('o');originalTimeZone=[TimeZoneInfo]::Local.Id;severity=if($e.Level -eq 1){'Critical'}else{'Error'};message=$message;simulated=$false}
                    $groups[$key]=[pscustomobject]@{log=$log;provider=$e.ProviderName;eventId=$e.Id;count=0;firstSeen=$time;lastSeen=$time;latest=$anchor}
                }
                $groups[$key].count++;$groups[$key].firstSeen=$time
            }
            $coverage.Add([pscustomobject]@{node=$source;log=$log;status='Collected';error=$null;matchingAtLeast=$records.Count;truncated=($records.Count -gt $limit)})
        }catch{$coverage.Add([pscustomobject]@{node=$source;log=$log;status='Not Assessed';error=$_.Exception.Message;truncated=$false})}
    }
    $sorted=@($groups.Values | Sort-Object log,provider,eventId)
    [pscustomobject]@{groups=$sorted;events=@($sorted | ForEach-Object {$_.latest});searches=@($coverage.ToArray());truncated=(@($coverage | Where-Object truncated).Count -gt 0);summaryLimit=$limit;start=$begin.ToString('o');end=$end.ToString('o');collectedAt=[datetime]::UtcNow.ToString('o');source=$source;targetTimeZone=(Read-BeaconTimeZone -StartUtc $begin -EndUtc $end);errorsOnly=$true}
}

function Read-BeaconNetwork($Destinations,$Limits,$DeadlineUtc) {
    $deadline=if($DeadlineUtc){[datetime]::Parse($DeadlineUtc).ToUniversalTime()}else{[datetime]::UtcNow.AddSeconds([int]$Limits.inspectionLimitSeconds)}
    foreach($d in @($Destinations)) {
        $r=[ordered]@{host=$d.host;port=[int]$d.port;enabled=$true;sourceServer=$source;mode='live';dns=@{status='Not Assessed';resolvedAddress=$null;error=$null};ping=@{sent=0;replies=0;timeouts=0;averageMs=$null;minimumMs=$null;maximumMs=$null;unansweredPercent=$null;probes=@();status='Not Assessed'};tcp=@{port=[int]$d.port;connected=$null;timingMs=$null;status='Not Assessed';error=$null};https=@{statusCode=$null;timingMs=$null;status='Not Assessed';error=$null;protocol=$d.protocol};trace=@{attempted=$false;attemptCount=0;sourceServer=$source;destination=$d.host;triggerReasons=@();hops=@();reached=$false;truncated=$false;explanation='No trace trigger.'};error=$null;startedAt=[datetime]::UtcNow.ToString('o')}
        if([datetime]::UtcNow -ge $deadline){$r.error='Connectivity inspection time budget exhausted.';$r.truncated=$true;[pscustomobject]$r;continue}
        try {
            $task=[Net.Dns]::GetHostAddressesAsync([string]$d.host)
            if(-not $task.Wait([int]$Limits.timeoutMs)){throw 'DNS timeout.'}
            $addresses=@($task.Result);if(-not $addresses.Count){throw 'No DNS addresses returned.'}
            $address=$addresses | Where-Object AddressFamily -eq InterNetwork | Select-Object -First 1
            if(-not $address){$address=$addresses[0]}
            $r.dns=@{status='Healthy';resolvedAddress=$address.IPAddressToString;error=$null}
        } catch { $r.dns.error=$_.Exception.Message;$r.dns.status='Warning';$r.error='DNS failed; address-based probes skipped.';$r.trace.explanation='DNS failed; no trace was attempted.';[pscustomobject]$r;continue }
        $ping=New-Object Net.NetworkInformation.Ping
        $latencies=New-Object 'Collections.Generic.List[double]'
        try {
            for($i=1;$i -le [int]$Limits.probeCount -and [datetime]::UtcNow -lt $deadline;$i++){
                $r.ping.sent++;$ms=$null;$timeout=$true
                try{$reply=$ping.Send($address,[int]$Limits.timeoutMs);if($reply.Status -eq 'Success'){$ms=[double]$reply.RoundtripTime;$timeout=$false;$latencies.Add($ms);$r.ping.replies++}}catch{}
                if($timeout){$r.ping.timeouts++};$r.ping.probes+=@{sequence=$i;latencyMs=$ms;timeout=$timeout}
            }
            if($latencies.Count){$stats=$latencies | Measure-Object -Average -Minimum -Maximum;$r.ping.averageMs=[math]::Round($stats.Average,2);$r.ping.minimumMs=$stats.Minimum;$r.ping.maximumMs=$stats.Maximum}
            if($r.ping.sent){$r.ping.unansweredPercent=100*$r.ping.timeouts/$r.ping.sent;$r.ping.status=if($r.ping.timeouts -or $r.ping.averageMs -gt $Limits.latencyThresholdMs){'Warning'}else{'Healthy'}}
            if([datetime]::UtcNow -lt $deadline){
                $client=New-Object Net.Sockets.TcpClient($address.AddressFamily);$timer=[Diagnostics.Stopwatch]::StartNew();$pending=$null
                try{$pending=$client.BeginConnect($address,[int]$d.port,$null,$null);if(-not $pending.AsyncWaitHandle.WaitOne([int]$Limits.timeoutMs)){throw 'TCP connection timeout.'};$client.EndConnect($pending);$r.tcp.connected=$true;$r.tcp.status='Healthy'}catch{$r.tcp.connected=$false;$r.tcp.status='Warning';$r.tcp.error=$_.Exception.Message}finally{$timer.Stop();$r.tcp.timingMs=$timer.ElapsedMilliseconds;if($pending){$pending.AsyncWaitHandle.Close()};$client.Close()}
            }
            if([datetime]::UtcNow -lt $deadline){
                $timer=[Diagnostics.Stopwatch]::StartNew();$response=$null
                try{
                    $builder=New-Object UriBuilder([string]$d.protocol,[string]$d.host,[int]$d.port,'/')
                    $http=[Net.HttpWebRequest]::Create($builder.Uri);$http.Method='HEAD';$http.Timeout=[int]$Limits.timeoutMs;$http.ReadWriteTimeout=[int]$Limits.timeoutMs;$http.AllowAutoRedirect=$false;$http.Proxy=$null
                    try{$response=$http.GetResponse()}catch [Net.WebException]{if($_.Exception.Response){$response=$_.Exception.Response}else{throw}}
                    $r.https.statusCode=[int]$response.StatusCode;$r.https.status=if([int]$response.StatusCode -ge 400){'Warning'}else{'Healthy'}
                }catch{$r.https.status='Warning';$r.https.error=$_.Exception.Message}finally{$timer.Stop();$r.https.timingMs=$timer.ElapsedMilliseconds;if($response){$response.Close()}}
            }
            $reasons=@();if($r.ping.timeouts){$reasons+='One or more unanswered ICMP probes.'};if($latencies.Count -and $r.ping.averageMs -gt $Limits.latencyThresholdMs){$reasons+='Average latency exceeded configured threshold.'}
            if($reasons.Count -and [datetime]::UtcNow -lt $deadline){
                $r.trace.attempted=$true;$r.trace.attemptCount=1;$r.trace.triggerReasons=$reasons;$r.trace.maxHops=[int]$Limits.maxHops;$r.trace.executionLimitSeconds=[int]$Limits.traceLimitSeconds
                $traceEnd=[datetime]::UtcNow.AddSeconds([int]$Limits.traceLimitSeconds);if($traceEnd -gt $deadline){$traceEnd=$deadline}
                $traceTimer=[Diagnostics.Stopwatch]::StartNew()
                for($hop=1;$hop -le [int]$Limits.maxHops -and [datetime]::UtcNow -lt $traceEnd;$hop++){
                    $remaining=[int][math]::Max(1,($traceEnd-[datetime]::UtcNow).TotalMilliseconds)
                    $opts=New-Object Net.NetworkInformation.PingOptions($hop,$true)
                    try{$reply=$ping.Send($address,[math]::Min([int]$Limits.timeoutMs,$remaining),([byte[]](0..31)),$opts);$ok=$reply.Status -eq 'Success';$r.trace.hops+=@{hop=$hop;address=if($reply.Address){$reply.Address.IPAddressToString}else{$null};timingsMs=@($reply.RoundtripTime);timeouts=if($reply.Status -eq 'TimedOut'){1}else{0};status=[string]$reply.Status};if($ok){$r.trace.reached=$true;break}}catch{$r.trace.hops+=@{hop=$hop;address=$null;timingsMs=@();timeouts=1;error=$_.Exception.Message}}
                }
                $traceTimer.Stop();$r.trace.elapsedMs=$traceTimer.ElapsedMilliseconds;$r.trace.truncated=-not $r.trace.reached;$r.trace.explanation='One bounded ICMP TTL trace; routers may filter responses. No path fault is inferred.'
            }elseif($reasons.Count){$r.trace.explanation='Trace trigger observed but inspection time budget exhausted.';$r.trace.truncated=$true}
        }finally{$ping.Dispose()}
        if([datetime]::UtcNow -ge $deadline){$r.truncated=$true}
        $r.completedAt=[datetime]::UtcNow.ToString('o');[pscustomobject]$r
    }
}

function Invoke-BeaconParallelNetwork($Destinations,$Limits) {
    if(-not @($Destinations).Count){return}
    $maximum=[math]::Min(32,[math]::Max(1,[int]$Limits.maxConcurrent))
    $deadline=[datetime]::UtcNow.AddSeconds([int]$Limits.inspectionLimitSeconds).ToString('o')
    $definition=${function:Read-BeaconNetwork}.ToString()
    $probe={
        param($Definition,$Destination,$Limits,$ExecutionSource,$DeadlineUtc)
        $ErrorActionPreference='Stop';$source=$ExecutionSource
        Set-Item -Path Function:\Read-BeaconNetwork -Value ([scriptblock]::Create($Definition))
        Read-BeaconNetwork @($Destination) $Limits $DeadlineUtc
    }
    # Match the original connectivity collector's runspace pool (1..6 by default).
    $pool=[runspacefactory]::CreateRunspacePool(1,$maximum)
    $pending=New-Object 'Collections.Generic.List[object]'
    try{
        $pool.Open()
        foreach($destination in @($Destinations)){
            $powershell=[powershell]::Create();$powershell.RunspacePool=$pool
            $null=$powershell.AddScript($probe.ToString()).AddArgument($definition).AddArgument($destination).AddArgument($Limits).AddArgument($source).AddArgument($deadline)
            $entry=[pscustomobject]@{PowerShell=$powershell;Handle=$null;Destination=$destination};$pending.Add($entry)
            $entry.Handle=$powershell.BeginInvoke()
        }
        foreach($entry in $pending){
            try{
                $result=$entry.PowerShell.EndInvoke($entry.Handle)
                if($entry.PowerShell.HadErrors){throw ($entry.PowerShell.Streams.Error | Out-String)}
                if(@($result).Count -ne 1){throw 'Probe worker did not return one destination result.'}
                $result
            }catch{[pscustomobject]@{host=$entry.Destination.host;port=$entry.Destination.port;sourceServer=$source;mode='live';error="Probe worker failed: $($_.Exception.Message)"}}
        }
    }finally{
        foreach($entry in $pending){
            if($entry.Handle -and -not $entry.Handle.IsCompleted){$entry.PowerShell.Stop()}
            $entry.PowerShell.Dispose()
        }
        $pool.Close();$pool.Dispose()
    }
}

function Open-BeaconSql([string]$Instance) {
    if($Instance -eq 'Auto'){
        $names=@();try{$names=@((Get-ItemProperty 'HKLM:/SOFTWARE/Microsoft/Microsoft SQL Server/Instance Names/SQL' -ErrorAction Stop).PSObject.Properties | Where-Object {$_.Name -notlike 'PS*'} | Select-Object -ExpandProperty Name)}catch{}
        if(-not $names.Count){throw 'No local SQL Server database-engine instance was discovered. Specify an installed instance or review SQL permissions.'}
        $Instance=if($names -contains 'MSSQLSERVER'){'MSSQLSERVER'}else{$names[0]}
        if($names.Count -gt 1){Add-Issue 'SQL instance scope' "Multiple instances discovered ($($names -join ', ')); this run samples $Instance. Select each other instance for a separate assessment."}
    }
    $builder=New-Object Data.SqlClient.SqlConnectionStringBuilder
    $builder.DataSource=if($Instance -eq 'MSSQLSERVER'){'.'}else{".\$Instance"}
    $builder.InitialCatalog='master';$builder.IntegratedSecurity=$true;$builder.ConnectTimeout=5;$builder.ApplicationName='OpsBeacon read-only assessment';$builder.Encrypt=$true;$builder.TrustServerCertificate=$false
    $conn=New-Object Data.SqlClient.SqlConnection($builder.ConnectionString)
    try{$conn.Open();return $conn}catch{$conn.Dispose();throw}
}
function Read-BeaconSql($Connection) {
    $command=$Connection.CreateCommand();$command.CommandTimeout=5
    $command.CommandText=@'
SELECT CAST(SERVERPROPERTY('ServerName') AS nvarchar(128)) AS ServerName,
 (SELECT cntr_value/1024.0 FROM sys.dm_os_performance_counters WHERE counter_name='Total Server Memory (KB)' AND object_name LIKE '%:Memory Manager%') AS TotalMB,
 (SELECT cntr_value/1024.0 FROM sys.dm_os_performance_counters WHERE counter_name='Target Server Memory (KB)' AND object_name LIKE '%:Memory Manager%') AS TargetMB,
 (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name='Memory Grants Pending' AND object_name LIKE '%:Memory Manager%') AS Grants,
 DATEDIFF(second,sqlserver_start_time,GETDATE())/60.0 AS UptimeMinutes FROM sys.dm_os_sys_info;
'@
    $reader=$null
    try{$reader=$command.ExecuteReader();if(-not $reader.Read()){throw 'SQL DMVs returned no measurements.'};$values=@{};foreach($name in @('TotalMB','TargetMB','Grants','UptimeMinutes','ServerName')){$v=$reader[$name];$values[$name]=if($v -is [DBNull]){$null}else{$v}};return [pscustomobject]$values}finally{if($reader){$reader.Dispose()};$command.Dispose()}
}

function Read-BeaconCluster($Options,$Rules) {
    try{
        Import-Module FailoverClusters -ErrorAction Stop
        $c=Get-Cluster -ErrorAction Stop;$nodes=@(Get-ClusterNode -Cluster $c.Name -ErrorAction Stop);$roles=@(Get-ClusterGroup -Cluster $c.Name -ErrorAction Stop);$resources=@(Get-ClusterResource -Cluster $c.Name -ErrorAction Stop);$q=Get-ClusterQuorum -Cluster $c.Name -ErrorAction Stop
        $w=$null;if($q.QuorumResource){$w=Get-ClusterResource -Name ([string]$q.QuorumResource) -Cluster $c.Name -ErrorAction Stop};$wType=if($w){[string]$w.ResourceType}else{'None'};$share=$null
        if($wType -eq 'File Share Witness'){try{$share=[string]($w | Get-ClusterParameter -Name SharePath -ErrorAction Stop).Value}catch{Add-Issue 'Cluster witness path' $_.Exception.Message}}
        $members=@();$index=0
        foreach($n in $nodes){
            $index++;$entry=[ordered]@{name=[string]$n.Name;state=[string]$n.State;collectionStatus='Not Assessed';measurements=$null;recentErrors=@();error=$null}
            if([string]$n.Name -ieq $source){$entry.measurements=$script:general.Measurements;$entry.collectionStatus='Collected'}elseif($index -le 16){
                try{
                    $definition=${function:Invoke-BeaconLocalCollection}.ToString()
                    $nodeBlock=[scriptblock]::Create("function Invoke-BeaconLocalCollection {`n$definition`n}; Invoke-BeaconLocalCollection")
                    $session=$null
                    try{$session=New-PSSession -ComputerName ([string]$n.Name) -SessionOption (New-PSSessionOption -OpenTimeout 5000 -OperationTimeout 30000) -ErrorAction Stop;$nodeResult=Invoke-Command -Session $session -ScriptBlock $nodeBlock -ErrorAction Stop;$entry.measurements=$nodeResult.Measurements;$entry.collectionStatus='Collected';if($nodeResult.Errors.Count){$entry.error=($nodeResult.Errors | ForEach-Object {$_.error}) -join '; '}}finally{if($session){Remove-PSSession $session}}
                }catch{$entry.error=$_.Exception.Message}
            }else{$entry.error='Node collection limit (16) reached.'}
            $members += [pscustomobject]$entry
        }
        $state=if(@($resources | Where-Object State -eq 'Failed').Count -or @($roles | Where-Object State -eq 'Failed').Count){'Critical'}elseif(@($nodes | Where-Object State -ne 'Up').Count -or @($roles | Where-Object State -ne 'Online').Count -or @($resources | Where-Object State -ne 'Online').Count -or ($w -and $w.State -ne 'Online')){'Warning'}elseif(@($members | Where-Object {-not $_.measurements -or $_.error}).Count){'Not Assessed'}else{'Healthy'}
        [pscustomobject]@{name=[string]$c.Name;status=$state;quorum=@{configuration=[string]$q.QuorumType;witnessType=$wType;fileSharePath=$share;status=if(-not $w -or $w.State -eq 'Online'){'Healthy'}else{'Warning'};evidence='Read-only Get-ClusterQuorum and resource state snapshot.'};nodes=$members;roles=@($roles | ForEach-Object {@{name=[string]$_.Name;state=[string]$_.State;owner=[string]$_.OwnerNode}});resources=@($resources | ForEach-Object {@{name=[string]$_.Name;type=[string]$_.ResourceType;state=[string]$_.State;owner=[string]$_.OwnerNode}});recentErrors=@();coverage=@(@{scope='Cluster member events and SQL workloads';status='Not Assessed';reason='Initial event/SQL collection covers the inspected node. Inspect each other member separately with authorized access; remote second-hop authentication may require delegation.'});observationPeriod='Live topology snapshot; member performance uses short read-only samples.';workloadNote='Cluster availability does not establish SQL or application health. No cluster validation, storage tests, failovers or configuration changes were executed.'}
    }catch{[pscustomobject]@{discoveryError=$_.Exception.Message;status='Not Assessed'}}
}

if($Request.action -eq 'events') { Read-BeaconEvents $Request.query; return }
$sqlConnection=$null;$sqlSamples=New-Object 'Collections.Generic.List[object]'
if($Request.options.sql){try{$sqlConnection=Open-BeaconSql $Request.options.sqlInstance}catch{Add-Issue 'SQL Server' $_.Exception.Message}}
try{
    # General collection uses actual counter deltas. SQL sampling runs alongside it on this target.
    $script:BeaconSqlConnection=$sqlConnection;$script:BeaconSqlSamples=$sqlSamples
    $script:general=Invoke-BeaconLocalCollection -ObservationSeconds ([int]$Request.options.observationSeconds) -SqlObserver {
        if($script:BeaconSqlConnection){try{$value=Read-BeaconSql $script:BeaconSqlConnection;$script:BeaconSqlSamples.Add([pscustomobject]@{timestamp=[datetime]::UtcNow.ToString('o');value=$value})}catch{Add-Issue 'SQL sample' $_.Exception.Message}}
    }
}finally{if($sqlConnection){$sqlConnection.Dispose()}}
$m=$general.Measurements
if($sqlSamples.Count){
    $last=$sqlSamples[$sqlSamples.Count-1].value;$m.sqlTotalMB=$last.TotalMB;$m.sqlTargetMB=$last.TargetMB;$m.grants=$last.Grants;$m.uptimeMinutes=$last.UptimeMinutes
    # Track warning and critical durations separately; a last-sample spike is not sustained pressure.
    $paired=@($general.Samples)
    if($paired.Count -eq $sqlSamples.Count){
        foreach($kind in @('pressureWarning','pressureCritical','grantsWarning','grantsCritical')){
            $runStart=$null;$duration=0.0;$complete=$true;$critical=$kind -like '*Critical'
            $grantsThreshold=if($critical){$Request.rules.grantsCritical}else{$Request.rules.grantsWarning}
            $memoryThreshold=if($critical){$Request.rules.osAvailableCriticalGB}else{$Request.rules.osAvailableWarningGB}
            for($i=0;$i -lt $paired.Count;$i++){
                $osSample=$paired[$i];$sqlSample=$sqlSamples[$i];$t=[datetime]::Parse($sqlSample.timestamp)
                if($null -eq $osSample.freeMemoryKB -or $null -eq $sqlSample.value.Grants){$complete=$false}
                $condition=$null -ne $sqlSample.value.Grants -and $sqlSample.value.Grants -ge $grantsThreshold
                if($kind -like 'pressure*'){$condition=$condition -and $null -ne $osSample.freeMemoryKB -and $osSample.freeMemoryKB/1MB -lt $memoryThreshold}
                if($condition){if($null -eq $runStart){$runStart=$t};$duration=($t-$runStart).TotalMinutes}else{$runStart=$null;$duration=0}
            }
            $minutes=if($complete){[math]::Round($duration,3)}else{$null}
            $m | Add-Member -NotePropertyName ($kind+'Minutes') -NotePropertyValue $minutes -Force
        }
        $m.pressureMinutes=$m.pressureWarningMinutes
    }
}
$network=@();if($Request.options.connectivity){$network=@(Invoke-BeaconParallelNetwork $Request.destinations $Request.connectivity)}
$cluster=$null;if($Request.options.cluster){$cluster=Read-BeaconCluster $Request.options $Request.rules}
$eventResult=$null
if($Request.options.events){$eventResult=Read-BeaconErrorSummary @{start=$started.AddHours(-[int]$Request.events.searchHours).ToString('o');end=[datetime]::UtcNow.ToString('o');summaryLimit=[int]$Request.events.summaryLimit}}
$targetTimeZone=if($eventResult){$eventResult.targetTimeZone}else{Read-BeaconTimeZone}
[pscustomobject]@{Target=$Request.options.target;ExecutionSource=$source;TargetTimeZone=$targetTimeZone;StartedAt=$started.ToString('o');CompletedAt=[datetime]::UtcNow.ToString('o');Measurements=$m;Samples=$general.Samples;SqlSamples=@($sqlSamples.ToArray());Connectivity=$network;Cluster=$cluster;EventResult=$eventResult;Errors=@($general.Errors)+@($issues.ToArray());Coverage=$general.Coverage}
