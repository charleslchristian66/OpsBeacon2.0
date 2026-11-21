import {installReportStyles,renderReport,downloadReadableReport,assessmentName} from './report-view.js';
import {createLiveReport,refreshLiveReport} from './live-report.js';
import {reportErrorGroups} from './event-summary.js';
import {formatTargetTime,reportTimeZone} from './time-display.js';
installReportStyles();
const $=id=>document.getElementById(id),esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const headers={'Content-Type':'application/json; charset=utf-8','X-OpsBeacon-Live':'1'};
let config,localTarget,report=null,busy=false,searchResults=[];
async function json(url,options){const response=await fetch(url,options);const value=await response.json();if(!response.ok)throw Error(value.Error??`Request failed (${response.status})`);return value;}
function showError(message){$('notice').hidden=false;$('notice').textContent=message;}
function setBusy(value){busy=value;for(const id of ['inspect','search-events'])$(id).disabled=value;document.querySelectorAll('[data-investigate],[data-error-group]').forEach(b=>b.disabled=value);$('inspect-form').setAttribute('aria-busy',String(value));}
async function collect(action,body,status){
  const job=await json(`/api/jobs/${action}`,{method:'POST',headers,body:JSON.stringify(body)}),start=Date.now();
  for(;;){
    const state=await json(`/api/jobs/${job.id}`);
    if(state.state==='Failed')throw Error(state.Error);
    if(state.state==='Completed')return state;
    status.textContent=`${state.state==='Queued'?'Queued for background collection':'Collecting'} on ${body.execution==='local'?'localhost':body.target} · ${Math.round((Date.now()-start)/1000)} seconds elapsed. You can keep this page open while checks run.`;
    if(Date.now()-start>35*60*1000)throw Error('Collection reporting deadline exceeded. Review the saved job status before retrying.');
    await new Promise(resolve=>setTimeout(resolve,1500));
  }
}
async function save(){
  $('save-status').textContent='Saving assessment…';$('saved-report').hidden=true;
  try{const saved=await json('/api/reports',{method:'POST',headers,body:JSON.stringify(report)});$('saved-report').href=saved.Url;$('saved-report').hidden=false;$('save-status').textContent='Saved locally';}
  catch(e){$('save-status').textContent='Save failed · download the report to preserve it.';showError(e.message);}
}
function render(){
  $('results').hidden=false;$('friendly-report').innerHTML=renderReport(report,{interactive:true});document.title=`Ops Beacon — ${assessmentName(report)}`;
  $('investigation-reports').innerHTML=(report.EventInvestigations??[]).length?'<h3>Event investigation reports</h3>'+report.EventInvestigations.map(inv=>`<p><a target="_blank" rel="noopener" href="/assets/investigation.html?id=${encodeURIComponent(report.AssessmentId)}&investigation=${encodeURIComponent(inv.id)}">Open report: Event ${esc(inv.anchor.eventId)} · ${esc(inv.anchor.provider)} · ${esc(formatTargetTime(inv.anchor.timestamp,reportTimeZone(report,inv),inv.anchor))} — Read / JSON / Print to PDF</a></p>`).join(''):'';
}
function renderOccurrences(items,zone=reportTimeZone(report)){
  searchResults=items;
  $('occurrences').innerHTML=items.length?`<div class="event-list">${items.map((e,i)=>`<article class="event-item"><b>${esc(e.eventId)} · ${esc(e.provider)} · ${esc(e.severity)}</b><small>${esc(formatTargetTime(e.timestamp,zone,e))} · ${esc(e.originalTimeZone??zone?.id??'Time zone not recorded')} · ${esc(e.server)} / ${esc(e.log)} / Record ${esc(e.recordId)}</small><p>${esc(e.message)}</p><button type="button" data-investigate="${i}">Investigate ±2 hours</button></article>`).join('')}</div>`:'<p>No occurrences in the returned sample. Review log coverage below.</p>';
}
function reportTarget(){return {target:report.Target,execution:report.Options.execution};}
function selectedLogs(){return [...document.querySelectorAll('.event-log:checked')].map(e=>e.value);}
$('execution').onchange=()=>{$('target').readOnly=$('execution').value==='local';$('target').value=$('execution').value==='local'?'localhost':'';};
$('profile').onchange=()=>{
  $('sql').checked=$('profile').value==='Database Server';$('cluster').checked=$('profile').value==='Cluster Node';
  $('events').checked=true;$('connectivity').checked=true;
  $('progress').textContent=`Ready · ${$('profile').value}`;
};
$('inspect-form').onsubmit=async event=>{
  event.preventDefault();if(busy)return;setBusy(true);$('notice').hidden=true;
  try{
    const destinations=$('destinations').value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean).map(line=>{const parts=line.split(',').map(p=>p.trim());if(parts.length!==3)throw Error('Use host, port, http or https for each destination.');return {host:parts[0],port:Number(parts[1]),protocol:parts[2]};});
    const body={target:$('execution').value==='local'?localTarget:$('target').value.trim(),execution:$('execution').value,profile:$('profile').value,observationSeconds:Number($('duration').value),sqlInstance:$('sql-instance').value.trim(),destinations};for(const id of ['sql','cluster','events','connectivity'])body[id]=$(id).checked;
    const state=await collect('assess',body,$('progress'));
    report=createLiveReport(state.result,state.options,config);render();renderOccurrences([]);await save();
    $('progress').textContent=`Completed · ${report.Profile} · ${report.Status} · ${report.Execution.actualSource}`;$('event-status').textContent='Select an error group in the report summary above, or search event occurrences below.';
  }catch(e){showError(e.message);$('progress').textContent='Collection failed · see the message below.';}
  finally{setBusy(false);}
};
$('friendly-report').onclick=async event=>{
  const button=event.target.closest('[data-error-group]');if(!button||busy||!report)return;
  const group=reportErrorGroups(report)[Number(button.dataset.errorGroup)];if(!group)return;
  setBusy(true);$('notice').hidden=true;$('event-id').value=group.eventId;
  try{
    const summary=report.Collection.EventResult;
    const state=await collect('events',{...reportTarget(),start:summary.start,end:summary.end,logs:[group.log],eventId:group.eventId,provider:group.provider,errorsOnly:true},$('event-status'));
    renderOccurrences(state.result.events??[],state.result.targetTimeZone);
    report.EventSearches??=[];report.EventSearches.push(state.result);refreshLiveReport(report);render();await save();
    const failures=(state.result.searches??[]).filter(s=>s.status!=='Collected');
    $('event-status').textContent=`${group.log} / ${group.provider} / Event ${group.eventId}: ${state.result.events.length} error occurrences returned${state.result.truncated?' (result limit reached)':''}. `+(failures.length?failures.map(s=>`${s.log}: ${s.status} — ${s.error??'Query did not complete.'}`).join(' | '):state.result.events.length?'Select a specific occurrence to create its ±2-hour report.':'No matching stored records were returned. The log may have been cleared or rolled over since this assessment.');
    if(failures.length)showError(failures.map(s=>`${s.log}: ${s.error??s.status}`).join(' | '));
    $('event-status').scrollIntoView({block:'start',behavior:'smooth'});
  }catch(e){showError(e.message);$('event-status').textContent='Could not load this error group.';}finally{setBusy(false);}
};
$('event-form').onsubmit=async event=>{
  event.preventDefault();if(busy||!report)return;setBusy(true);$('notice').hidden=true;
  try{
    const end=new Date(),start=new Date(end-Number($('event-hours').value)*3600000);
    const state=await collect('events',{...reportTarget(),start:start.toISOString(),end:end.toISOString(),logs:selectedLogs(),eventId:$('event-id').value},$('event-status'));
    const r=state.result;renderOccurrences(r.events??[],r.targetTimeZone);
    // Preserve searched occurrences separately from the original assessment period.
    report.EventSearches??=[];report.EventSearches.push(r);
    refreshLiveReport(report);render();
    $('event-status').textContent=`${r.events.length} occurrences returned${r.truncated?' · result cap reached':''}. `+r.searches.map(s=>`${s.log}: ${s.status}${s.error?' — '+s.error:''}`).join(' | ');
    await save();
  }catch(e){showError(e.message);$('event-status').textContent='Event search failed.';}finally{setBusy(false);}
};
$('occurrences').onclick=async event=>{
  const button=event.target.closest('[data-investigate]');if(!button||busy)return;
  const anchor=searchResults[Number(button.dataset.investigate)];if(!anchor)return;setBusy(true);$('notice').hidden=true;
  try{
    const center=new Date(anchor.timestamp),start=new Date(+center-7200000),end=new Date(+center+7200000);
    const logs=['System','Application',...(selectedLogs().includes('Microsoft-Windows-FailoverClustering/Operational')||anchor.log==='Microsoft-Windows-FailoverClustering/Operational'?['Microsoft-Windows-FailoverClustering/Operational']:[])];
    const state=await collect('events',{...reportTarget(),start:start.toISOString(),end:end.toISOString(),logs},$('event-status'));
    const result=state.result,errors=result.searches.filter(s=>s.status!=='Collected').map(s=>({scope:`${s.node} / ${s.log}`,error:s.error}));
    const coverage=result.events.some(e=>e.key===anchor.key)?[]:[{scope:'Selected event occurrence',reason:'The selected occurrence was not returned by the follow-up query. Review truncation, log rollover and access; the original anchor is preserved separately.'}];
    report.EventInvestigations.push({id:crypto.randomUUID(),assessmentId:report.AssessmentId,mode:'live',anchor,window:{beforeHours:2,afterHours:2,start:start.toISOString(),end:end.toISOString()},displayTimeZone:result.targetTimeZone?.id??anchor.originalTimeZone??'UTC',targetTimeZone:result.targetTimeZone,collectedAt:result.collectedAt,investigatedAt:new Date().toISOString(),logsSearched:result.searches.map(s=>s.log),nodesSearched:[result.source],searches:result.searches,timeline:result.events,totalMatching:result.totalMatchingAtLeast,maxEvents:config.events.maxEvents,truncated:result.truncated,incompleteFollowUp:+end>Date.parse(result.collectedAt),errors,coverage,interpretation:'Time proximity does not establish cause. Scope is the assessed computer.'});
    refreshLiveReport(report);render();await save();$('event-status').textContent=`Investigation report created · ${result.events.length} timeline events${result.truncated?' · result cap reached — incomplete timeline':''}. Open its report below to read, download JSON, or print to PDF.`;$('investigation-reports').scrollIntoView({block:'start',behavior:'smooth'});
  }catch(e){showError(e.message);$('event-status').textContent='Investigation failed.';}finally{setBusy(false);}
};
$('download-readable').onclick=()=>downloadReadableReport(report);
$('print-report').onclick=()=>window.print();
$('download-json').onclick=()=>{if(!report)return;const url=URL.createObjectURL(new Blob([JSON.stringify(report,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=`OpsBeacon-${report.AssessmentId}.json`;a.click();setTimeout(()=>URL.revokeObjectURL(url),2000);};
try{const info=await json('/api/config');config=info.config;localTarget=info.target;$('target').value='localhost';$('identity').textContent=`This computer: ${info.target} · Running as ${info.identity}`;$('destinations').value=`127.0.0.1, ${location.port}, http`;}
catch(e){showError(e.message);$('inspect').disabled=true;}
