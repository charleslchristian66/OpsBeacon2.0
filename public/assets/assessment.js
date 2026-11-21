export const worst = statuses => statuses.includes('Critical')?'Critical':statuses.includes('Warning')?'Warning':statuses.includes('Not Assessed')||!statuses.length?'Not Assessed':'Healthy';
export function volumeStatus(volume,rules){
  return volume.error||!Number.isFinite(volume.totalBytes)||volume.totalBytes<=0||!Number.isFinite(volume.freeBytes)||volume.freeBytes<0||volume.freeBytes>volume.totalBytes||!Number.isFinite(volume.freePercent)||volume.freePercent<0||volume.freePercent>100?'Not Assessed':volume.freePercent<rules.diskFreeCritical?'Critical':volume.freePercent<rules.diskFreeWarning?'Warning':'Healthy';
}
export function assessHealth(m, options, rules) {
  const sql=options.profile==='Microsoft SQL Server', supported=options.os==='Windows';
  const local=m.localSnapshot===true;
  const period=local?`Measured snapshot: ${m.observationSeconds} seconds; sustained health not established`:`${rules.observationMinutes} min requested; ${m.sampledMinutes??0} min available`;
  const cards=[];
  function add(id,label,value,units,status,rule,evidence,next,observation=period) {
    cards.push({id,label,value,units,status,rule,evidence,next,observationPeriod:observation});
  }
  const enough=local?m.observationSeconds>0:m.sampledMinutes!==null && m.sampledMinutes>=rules.observationMinutes;
  function high(id,label,value,units,warn,critical,next) {
    const missing=(value===null||value===undefined)||!enough;
    add(id,label,value,units,missing?'Not Assessed':value>=critical?'Critical':value>=warn?'Warning':'Healthy',
      `Warning ≥ ${warn} ${units}; Critical ≥ ${critical} ${units}${local?' (short snapshot thresholds only)':` for ${rules.observationMinutes} min`}`,
      missing?'Required measurement or observation coverage is missing.':`${label} measured ${value} ${units} over the available sample.`,next);
  }
  high('cpu','CPU utilization',m.cpu,'%',rules.cpuWarning,rules.cpuCritical,'Review workload and process CPU during this period.');
  if(sql && supported) {
    const missing=m.memoryUsed===null||m.availableGB===null||m.grants===null||m.pressureMinutes===null||!enough;
    const sustained=m.pressureMinutes>=rules.pressureMinutes;
    const pressure=m.availableGB<rules.osAvailableWarningGB && m.grants>=rules.grantsWarning && sustained;
    add('memory','Memory utilization',m.memoryUsed,'%',missing?'Not Assessed':pressure?(m.availableGB<rules.osAvailableCriticalGB && m.grants>=rules.grantsCritical?'Critical':'Warning'):'Healthy',
      `SQL pressure requires OS available < ${rules.osAvailableWarningGB} GB AND grants ≥ ${rules.grantsWarning} for ≥ ${rules.pressureMinutes} min; Critical requires < ${rules.osAvailableCriticalGB} GB AND grants ≥ ${rules.grantsCritical}.`,
      missing?'Required SQL pressure evidence or coverage is unavailable.':`${m.availableGB} GB OS memory available; ${m.grants} pending grants sustained ${m.pressureMinutes} min. High use alone is not pressure.`,
      'Review OS headroom, query workspace grants and SQL max server memory together.');
  } else high('memory','Memory utilization',m.memoryUsed,'%',rules.memoryWarning,rules.memoryCritical,'Review available OS memory and processes using memory.');
  if(Array.isArray(m.volumes)){
    m.volumes.forEach((v,i)=>{
      const path=(v.mountPaths??[]).join(', ')||v.id;
      add(`storage-volume-${i}`,`Storage capacity · ${path}`,Number.isFinite(v.freePercent)?Number(v.freePercent.toFixed(2)):null,'% free',volumeStatus(v,rules),
        `Free space: Warning < ${rules.diskFreeWarning}%; Critical < ${rules.diskFreeCritical}%`,
        volumeStatus(v,rules)==='Not Assessed'?(v.error||'Volume capacity unavailable.'):`${(v.freeBytes/1073741824).toFixed(2)} GiB free of ${(v.totalBytes/1073741824).toFixed(2)} GiB on ${path}${v.label?` (${v.label})`:''}.`,
        'Review volume growth, retention and free capacity; do not delete files without review.','Mounted-volume capacity snapshot');
    });
    if(!m.volumes.length||m.volumeCapacityStatus!=='Collected')add('storage-coverage','Mounted-volume discovery',null,'','Not Assessed','All mounted volumes must be discoverable.','Mounted-volume discovery was empty or incomplete; see collection errors.','Check volume access using the inspected execution identity.','Capacity snapshot');
  }else{
  const diskMissing=m.diskFree===null||m.diskFree===undefined||!enough;
  add('storage','Storage capacity',m.diskFree,'% free',diskMissing?'Not Assessed':m.diskFree<rules.diskFreeCritical?'Critical':m.diskFree<rules.diskFreeWarning?'Warning':'Healthy',
    `Free space: Warning < ${rules.diskFreeWarning}%; Critical < ${rules.diskFreeCritical}%`,
    diskMissing?'Disk measurement or coverage unavailable.':`${m.diskFree}% free of ${m.diskTotalGB} GB on ${m.diskLabel??(options.os==='Windows'?'C:':'/')}.`,
    'Review growth, retention and free capacity; do not delete files without review.');
  }
  high('latency','System-drive storage latency',m.storageMs,'ms',rules.storageWarningMs,rules.storageCriticalMs,'Compare system-drive read/write latency, queue depth and workload baseline.');
  if (sql) {
    const missing=!supported||m.sqlTotalMB===null||m.sqlTargetMB===null||m.uptimeMinutes===null||!enough;
    add('sql-memory','SQL total / target memory',missing?null:`${m.sqlTotalMB} / ${m.sqlTargetMB}`,'MB',missing?'Not Assessed':'Healthy',
      'Total versus target is contextual; a gap alone does not establish pressure.',
      !supported?'This SQL collector supports Windows only.':missing?'SQL counters or observation coverage unavailable.':`Uptime ${m.uptimeMinutes} min. ${m.uptimeMinutes<30?'Startup / warm-up can explain a large total-to-target gap.':'Compare allocation with workload demand and OS headroom.'}`,
      'Correlate allocation trend, startup time, grants and OS memory.');
    const gMissing=!supported||m.grants===null||m.pressureMinutes===null||!enough;
    add('sql-grants','Memory Grants Pending',gMissing?null:m.grants,'requests',gMissing?'Not Assessed':m.pressureMinutes>=rules.pressureMinutes && m.grants>=rules.grantsCritical?'Critical':m.pressureMinutes>=rules.pressureMinutes && m.grants>=rules.grantsWarning?'Warning':'Healthy',
      `Sustained ≥ ${rules.pressureMinutes} min: Warning ≥ ${rules.grantsWarning}; Critical ≥ ${rules.grantsCritical}`,
      gMissing?'SQL grants or observation coverage unavailable / unsupported.':`${m.grants} requests pending for ${m.pressureMinutes} min.`,
      'Inspect waiting queries and workspace grants; correlate with OS memory.');
  }
  return cards;
}
export function assessConnectivity(items) {
  return items.filter(x=>!x.disabled).map((x,i)=>({id:`network-${i}`,label:x.host,status:x.dns?worst([x.dns.status,x.ping.status,x.tcp.status,x.https.status]):'Not Assessed',
    evidence:x.error||`${x.ping.replies}/${x.ping.sent} ping replies; TCP ${x.tcp.status}; ${(x.https.protocol??'https').toUpperCase()} ${x.https.statusCode??'unavailable'}.`,
    next:'Compare DNS, ICMP, TCP and HTTPS evidence independently. Filtering/rate limiting can suppress ping; path indicators do not prove a faulty NIC.',
    rule:'Independent DNS / ping / TCP / HTTPS checks; ping failure alone does not establish an outage.',observationPeriod:'Live inspection snapshot'}));
}
export function assessCluster(cluster,options,rules) {
  if (!cluster) return [];
  if(cluster.discoveryError) return [{id:'cluster-discovery',label:'Cluster discovery',status:'Not Assessed',evidence:cluster.discoveryError,next:'Establish read-only access on the inspected node.',rule:'Discovery must succeed before cluster assessment.',observationPeriod:'Live snapshot'}];
  const findings=[{id:'cluster-availability',label:'Cluster availability',status:cluster.status,evidence:`${cluster.nodes.length} discovered nodes; witness ${cluster.quorum.status}; roles ${cluster.roles.map(r=>r.state).join(', ')}.`,
    next:'Review quorum, resource state, recent errors and member coverage. Online resources do not prove SQL workload health.',rule:'Failed resource → Critical; witness or member coverage concern → Warning.',observationPeriod:cluster.observationPeriod}];
  cluster.nodes.forEach((node,i)=>{
    if(!node.measurements) findings.push({id:`node-${i}`,label:node.name,status:'Not Assessed',evidence:node.error,next:'Restore authorized read-only remote collection.',rule:'Unreachable member remains a coverage gap.',observationPeriod:'No node sample'});
    else assessHealth(node.measurements,options,rules).forEach(card=>findings.push({...card,id:`node-${i}-${card.id}`,label:`${node.name} · ${card.label}`}));
  });
  return findings;
}
