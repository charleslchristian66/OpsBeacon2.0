import {assessHealth,assessConnectivity,assessCluster,worst} from './assessment.js';
import {reportErrorGroups} from './event-summary.js';
const gap=(scope,reason)=>({scope,reason});
export function refreshLiveReport(r){
  const cards=assessHealth(r.Measurements,{...r.Options,profile:'General Purpose'},r.Rules);
  const reboot=r.Measurements.pendingReboot;
  const rebootStatus=reboot?.pending===true?'Warning':reboot?.pending===false&&reboot.coverage==='Collected'?'Healthy':'Not Assessed';
  cards.push({id:'pending-reboot',label:'Pending reboot',value:reboot?.pending===true?'Detected':rebootStatus==='Healthy'?'Not detected':'Unknown',units:'',status:rebootStatus,
    rule:'Warning when any checked Windows reboot indicator is present. Healthy requires all checked indicators to be readable and absent.',
    evidence:reboot?.pending===true?`Detected: ${(reboot.reasons??[]).join('; ')}.${reboot.coverage!=='Collected'?' Some indicators could not be read; see collection limits.':''}`:rebootStatus==='Healthy'?'No pending reboot indicators were detected in the checked Windows registry locations.':'Pending reboot status is unavailable or incomplete. Run a new assessment with access to the target registry.',
    next:reboot?.pending===true?'Review the indicator details and coordinate a restart through your normal maintenance process. Pending file operations may include stale entries.':rebootStatus==='Healthy'?'No restart is indicated by these checks. Other software may use additional reboot signals.':'Review collection access and run a new assessment.',observationPeriod:'Point-in-time registry check on the inspected target'});
  if(r.Options.sql){
    const m=r.Measurements,rule=r.Rules,period=`${m.observationSeconds} seconds measured`,duration=rule.pressureMinutes;
    cards.push(...assessHealth(m,{...r.Options,profile:'Microsoft SQL Server'},rule).filter(c=>c.id==='sql-memory'));
    for(const [id,label,kind] of [['sql-pressure','SQL / OS memory pressure','pressure'],['sql-grants','Memory Grants Pending','grants']]){
      const warning=m[kind+'WarningMinutes'],critical=m[kind+'CriticalMinutes'];
      const covered=Number.isFinite(warning)&&Number.isFinite(critical)&&m.observationSeconds>=duration*60;
      const status=!covered?'Not Assessed':critical>=duration?'Critical':warning>=duration?'Warning':'Healthy';
      cards.push({id,label,value:m.grants??null,units:'pending requests',status,rule:`At least ${duration} minutes continuously above grants thresholds (Warning ${rule.grantsWarning}, Critical ${rule.grantsCritical})${kind==='pressure'?` with OS available memory below ${rule.osAvailableWarningGB} / ${rule.osAvailableCriticalGB} GB respectively`:''}.`,evidence:covered?`${m.availableGB} GB OS memory available; ${m.grants} pending grants. ${warning} minutes at warning conditions; ${critical} minutes at critical conditions.`:`${m.observationSeconds} seconds observed; at least ${duration} minutes of complete SQL and OS samples are required. High memory use alone does not establish SQL pressure.`,next:'Correlate query workspace grants, SQL allocation, OS headroom and workload.',observationPeriod:period});
    }
  }
  r.Health={Status:worst(cards.map(c=>c.status)),Cards:cards};
  r.Findings=[...cards,...assessConnectivity(r.Connectivity),...assessCluster(r.Cluster,{...r.Options,profile:'General Purpose'},r.Rules)];
  r.CollectionErrors=[...(r.Collection.Errors??[])];r.MissingCoverage=[];r.Truncation=[];
  r.MissingCoverage.push(gap('Observation period',`${r.Measurements.observationSeconds} seconds measured. CPU and memory are sample averages; thresholds describe this observation and do not prove sustained server health.`));
  if(!r.Options.connectivity||!r.Connectivity.length)r.MissingCoverage.push(gap('Connectivity','No destinations were assessed.'));
  if(!r.Options.sql)r.MissingCoverage.push(gap('SQL Server','Disabled for this assessment.'));
  if(!r.Options.cluster)r.MissingCoverage.push(gap('Cluster','Disabled for this assessment.'));
  if(!r.Options.events)r.MissingCoverage.push(gap('Windows events','Disabled for this assessment.'));
  for(const s of r.Collection.EventResult?.searches??[]){if(s.status!=='Collected')r.CollectionErrors.push({scope:`${s.node} / ${s.log}`,error:s.error});}
  if(r.Collection.EventResult?.truncated)r.Truncation.push(gap('Error summary',`Error scan limit reached (${r.Collection.EventResult.summaryLimit??r.EventConfiguration.maxEvents} per log); counts cover the scanned records only.`));
  r.EventCollection={searches:r.Collection.EventResult?.searches??[],coverage:[],errors:[]};
  if(r.Cluster?.discoveryError)r.CollectionErrors.push({scope:'Cluster discovery',error:r.Cluster.discoveryError});
  for(const c of r.Cluster?.coverage??[])r.MissingCoverage.push(gap(c.scope,c.reason));
  for(const n of r.Cluster?.nodes??[])if(n.error)r.CollectionErrors.push({scope:n.name,error:n.error});
  for(const c of r.Connectivity){if(c.error)r.CollectionErrors.push({scope:c.host,error:c.error});if(c.truncated||c.trace?.truncated)r.Truncation.push(gap(c.host,'Connectivity inspection or trace limits reached.'));}
  for(const [index,g] of reportErrorGroups(r).entries()){r.Findings.push({id:`event-group-${index}`,label:`${g.provider} · event ${g.eventId}`,status:'Warning',evidence:`${g.log}: ${g.count} error occurrence(s). Most recent: ${g.lastSeen}.`,rule:'Error counts are grouped by log, source and Event ID; they do not prove root cause.',observationPeriod:`Recent ${r.EventConfiguration.searchHours} hours; see summary coverage`,next:'Select this group in the error summary, then choose an occurrence to investigate.'});}
  for(const i of r.EventInvestigations){
    r.CollectionErrors.push(...i.errors);r.MissingCoverage.push(...i.coverage);
    if(i.truncated)r.Truncation.push(gap('Event investigation','Result cap reached; narrow the event query.'));
    if(i.incompleteFollowUp)r.MissingCoverage.push(gap('Event investigation','The follow-up window extends beyond collection time.'));
  }
  for(const s of r.EventSearches??[]){
    for(const c of s.searches??[])if(c.status!=='Collected')r.CollectionErrors.push({scope:`Event search: ${c.node} / ${c.log}`,error:c.error});
    if(s.truncated)r.Truncation.push(gap('Event search','Result cap reached; narrow the event query.'));
  }
  r.Findings.forEach(f=>{if(f.status==='Not Assessed')r.MissingCoverage.push(gap(f.label,f.evidence));});
  for(const [i,g] of [...r.CollectionErrors.map(e=>gap(e.scope,e.error)),...r.MissingCoverage,...r.Truncation].entries())r.Findings.push({id:`coverage-${i}`,label:g.scope,status:'Not Assessed',evidence:g.reason,rule:'Missing, limited or short observations cannot establish complete health.',observationPeriod:'See collection limits',next:'Review the gap and collect the missing evidence.'});
  r.Status=worst(r.Findings.map(f=>f.status));r.UpdatedAt=new Date().toISOString();
  r.HumanSummary={Headline:r.Status==='Warning'||r.Status==='Critical'?`${r.Status} · review the findings and suggested next steps.`:'Measurements collected. Review collection limits before drawing conclusions.'};
  return r;
}
export function createLiveReport(collection,options,config){
  const id=crypto.randomUUID();return refreshLiveReport({SchemaVersion:'2.0.0',AssessmentId:id,RunId:id,Mode:'live',Designation:'Actual read-only Windows collection',Target:options.target,Platform:'Windows',Profile:options.profile??(options.sql?'General Purpose + SQL Server':'General Purpose Server'),Options:options,StartedAt:collection.StartedAt,CompletedAt:collection.CompletedAt,Execution:{requestedSource:options.target,actualSource:collection.ExecutionSource,liveExecutionEstablished:true,portalFallbackAllowed:false,scope:options.execution==='local'?'Explicit local collection':'Authenticated Windows remoting'},EnabledCapabilities:{general:true,sql:options.sql,cluster:options.cluster,events:options.events,connectivity:options.connectivity},Rules:structuredClone(config.rules),RuleDesignation:'Provisional snapshot thresholds; calibrate to your workload',ConnectivityConfiguration:structuredClone(config.connectivity),EventConfiguration:structuredClone(config.events),Collection:collection,Measurements:collection.Measurements,Connectivity:collection.Connectivity??[],Cluster:collection.Cluster,Events:collection.EventResult?.events??[],EventInvestigations:[],Interpretation:'Actual measurements collected on the identified execution source. CPU and memory are sample averages; capacity covers mounted volumes visible to the inspected execution identity; storage latency covers the system drive. Short observations do not establish sustained conditions. Read-only SQL and cluster discovery require installed roles and authorized access. Laptop workloads and power management affect results. Findings guide investigation and do not prove root cause.'});
}
