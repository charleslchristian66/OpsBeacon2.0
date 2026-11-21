import {assessConnectivity,volumeStatus} from './assessment.js';
import {reportErrorGroups} from './event-summary.js';
import {reportTheme} from './report-theme.js';
import {formatTargetTime,reportTimeZone,timeZoneLabel} from './time-display.js';

const esc=value=>String(value??'Not available').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const statuses=['Healthy','Warning','Critical','Not Assessed'];
const badge=value=>{const s=statuses.includes(value)?value:'Not Assessed';return `<span class="report-badge ${s.toLowerCase().replaceAll(' ','-')}">${s==='Healthy'?'✓ ':s==='Not Assessed'?'— ':'! '}${s}</span>`;};
const list=items=>`<ul>${items.map(item=>`<li>${esc(item)}</li>`).join('')}</ul>`;
const section=(title,body)=>`<section class="report-section"><h2>${esc(title)}</h2>${body}</section>`;
const table=(heads,rows,className='')=>`<div class="report-table-wrap"><table class="${esc(className)}"><thead><tr>${heads.map(h=>`<th scope="col">${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>`;
const cells=items=>`<tr>${items.map(x=>`<td>${esc(x)}</td>`).join('')}</tr>`;
const value=(v,unit='')=>v===null||v===undefined?'Not available':`${v}${unit?' '+unit:''}`;

const baseReportStyles=`
.report-document{background:#fff;color:#243347;border:1px solid #d5dfe6;border-radius:8px;padding:38px;line-height:1.6;font:14px/1.6 "Segoe UI",Arial,sans-serif;overflow-wrap:anywhere;max-width:1060px;margin:20px auto}
.report-document *{box-sizing:border-box}.report-document h1{font-size:30px;letter-spacing:-.7px;color:#142e40;margin:6px 0 12px}.report-document h2{color:#19394c;font-size:19px;letter-spacing:0;margin:0 0 14px}.report-document h3{color:#243347;font-size:15px;letter-spacing:0;margin:0 0 6px}.report-document p{margin:8px 0 12px}.report-document .report-kicker{font-size:11px;font-weight:700;color:#336859;letter-spacing:1.5px;text-transform:uppercase}.report-heading{border-bottom:3px solid #2d7b68;padding-bottom:22px;display:flex;justify-content:space-between;align-items:start;gap:15px}.report-subtitle{color:#536578}.report-document .report-mode{background:#eaf1f6;border:1px solid #cad9e4;color:#244f6c;padding:10px 14px;margin:20px 0;font-weight:600}.report-document .report-mode.simulated{background:#fff5da;border-color:#e4cc83;color:#745213}.report-meta{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px 26px;margin:18px 0}.report-meta dt{font-size:11px;text-transform:uppercase;letter-spacing:.6px;color:#637386}.report-meta dd{margin:2px 0 0;color:#243347}.report-section{border-top:1px solid #d9e2e8;padding-top:24px;margin-top:24px}.report-counts{display:flex;gap:9px;flex-wrap:wrap;margin:18px 0}.report-counts span{padding:9px 13px;background:#f1f5f7;border-radius:5px;font-size:12px}.report-document .report-badge{display:inline-block;font:600 11px/1.4 "Segoe UI",Arial,sans-serif;border:1px solid #82909c;padding:4px 9px;border-radius:4px;color:#445566;background:#edf1f4;white-space:nowrap;letter-spacing:0}.report-document .report-badge.healthy{background:#eaf5ee;color:#215b38;border-color:#8fbaa0}.report-document .report-badge.warning{background:#fff4d8;color:#77520b;border-color:#d6b66a}.report-document .report-badge.critical{background:#ffeded;color:#a12525;border-color:#d99a9a}.report-finding{border-left:3px solid #d5b052;background:#faf8f1;padding:16px 18px;margin:13px 0;break-inside:avoid}.report-finding.critical{border-color:#bb4949;background:#fff5f5}.report-finding .report-finding-heading{display:flex;gap:15px;justify-content:space-between;align-items:start}.report-document .report-next{font-weight:600;color:#254d46}.report-document ul{padding-left:22px}.report-document li{margin:7px 0}.report-document table{width:100%;border-collapse:collapse;font:12px/1.6 "Segoe UI",Arial,sans-serif;text-align:left;table-layout:auto;margin:12px 0}.report-document th{font:600 11px/1.5 "Segoe UI",Arial,sans-serif;color:#334e61;background:#edf3f6;letter-spacing:0}.report-document td,.report-document th{padding:11px 10px;border-bottom:1px solid #d8e1e7;vertical-align:top}.report-table-wrap{overflow-x:auto}.report-document .report-note{background:#f0f5f8;padding:14px 18px;border-radius:4px;color:#455d70;font-size:12px}.report-document details{margin:16px 0}.report-document summary{color:#315d77;font-weight:600;cursor:pointer}.report-document .report-muted{color:#607184;font-size:12px}.report-document .report-timeline{border-left:2px solid #b9cec8;padding-left:16px;margin:12px 0}.report-document .report-timeline p{font-size:12px}.report-document .report-footer{border-top:1px solid #ccd9e0;margin-top:30px;padding-top:14px;color:#607184;font-size:11px}.report-toolbar{display:flex;flex-wrap:wrap;gap:12px;align-items:center;margin:20px auto;max-width:1060px;font:14px "Segoe UI",Arial,sans-serif}.report-toolbar button,.report-toolbar a{padding:10px 16px;border:1px solid #476675;border-radius:5px;background:#fff;color:#173c4d;text-decoration:none;cursor:pointer}.report-standalone{margin:0;padding:16px;background:#edf2f5;color:#243347;font:14px "Segoe UI",Arial,sans-serif}.report-standalone .report-document{margin-top:0}
@media(max-width:650px){.report-document{padding:20px 15px}.report-heading{flex-direction:column}.report-meta{grid-template-columns:1fr}.report-document h1{font-size:25px}.report-document table{font-size:11px}.report-document td,.report-document th{padding:8px 6px}.report-finding .report-finding-heading{flex-wrap:wrap}}
@media print{@page{margin:15mm}.sidebar,.topbar,.page-heading,#notice,footer,#tab-inspect,#tab-events,.report-controls,.report-technical,#report-note,#save-status,#report-intro,.report-toolbar{display:none!important}.workspace{margin:0!important}body,main,.report-standalone{background:white!important;padding:0!important;color:#243347!important}#tab-report{display:block!important}#tab-report>.panel{border:0;padding:0;background:white}.report-document{border:0;padding:0;max-width:none;margin:0;font-size:11px}.report-document h2{break-after:avoid}.report-document tr{break-inside:avoid}.report-table-wrap{overflow:visible}.report-document details>*{display:block!important}.report-document details>summary{display:none!important}.report-document h1{font-size:25px}.report-document .report-badge{print-color-adjust:exact}.report-document .report-mode{print-color-adjust:exact}}
`;

export const reportStyles=baseReportStyles+reportTheme;

export function installReportStyles(){
  if(document.getElementById('friendly-report-styles'))return;
  const style=document.createElement('style');style.id='friendly-report-styles';style.textContent=reportStyles;document.head.append(style);
  window.addEventListener('beforeprint',expandReportForPrint);
}

function expandReportForPrint(){
  const closed=[...document.querySelectorAll('.report-document details:not([open])')];
  closed.forEach(element=>element.open=true);
  window.addEventListener('afterprint',()=>closed.forEach(element=>element.open=false),{once:true});
}

export const assessmentName=report=>report?.Mode==='live'&&report.Options?.execution==='local'?'localhost':report?.Target;

export function renderReport(r,{interactive=false}={}){
  if(!r)return '<p class="muted">Run an inspection to generate an assessment report.</p>';
  const findings=r.Findings??[],cards=r.Health?.Cards??[],local=r.Mode==='local',live=r.Mode==='live';
  const date=value=>formatTargetTime(value,reportTimeZone(r));
  const concerns=findings.filter(f=>['Critical','Warning'].includes(f.status)).sort((a,b)=>(a.status==='Critical'?0:1)-(b.status==='Critical'?0:1));
  const counts=statuses.map(s=>`<span><b>${findings.filter(f=>f.status===s).length}</b> ${s==='Not Assessed'?'not assessed':s.toLowerCase()}</span>`).join('');
  const gaps=[...(r.MissingCoverage??[]),...(r.CollectionErrors??[]).map(e=>({scope:e.scope,reason:e.error})),...(r.Truncation??[]).map(e=>({scope:e.scope,reason:e.reason}))];
  const gapLines=[...new Set(gaps.filter(g=>g.scope!=='Event collection coverage'||!(r.EventCollection?.coverage??[]).some(c=>g.reason===`${c.scope}: ${c.reason}`)).map(g=>`${g.scope}: ${local&&g.scope==='Connectivity coverage'?'Network checks are not enabled for laptop mode.':g.reason}`))];
  const summary=concerns.length?`${concerns.length} finding${concerns.length===1?' needs':'s need'} attention. Start with the items below, then review the measurements and collection limits.`:r.Status==='Healthy'?'No concerns were detected by the available checks. Review the scope and observation period before drawing conclusions.':'The available checks do not provide a complete assessment. Review the collection gaps before drawing conclusions.';
  let html=`<article class="report-document" aria-label="Assessment report"><header class="report-heading"><div><div class="report-kicker">Ops Beacon 2.0 / Assessment report</div><h1>${esc(assessmentName(r))}</h1><p class="report-subtitle">${esc(r.Profile)} · ${esc(r.Platform)}${r.Cluster?.name?' · Cluster member':r.Options?.cluster&&!live?' · Cluster node':''}</p></div>${badge(r.Status)}</header>
    <p class="report-mode ${live?'live':local?'local':'simulated'}">${live?'Live measurements · Read-only Windows collection':local?'Real laptop measurements · Read-only local collection':'Demonstration · All measurements and events are simulated'}</p>
    <dl class="report-meta"><div><dt>Assessment completed</dt><dd>${esc(date(r.CompletedAt))}</dd></div><div><dt>Observation period</dt><dd>${esc((local||live)?`${r.Measurements?.observationSeconds??'Unknown'} seconds · Snapshot averages; sustained health not established`:cards[0]?.observationPeriod??'See measurement evidence')}</dd></div><div><dt>Collection source</dt><dd>${esc((local||live)?r.Execution?.actualSource??'Not established':`Simulated target: ${r.Target}`)}</dd></div><div><dt>Report updated</dt><dd>${esc(date(r.UpdatedAt))}</dd></div></dl>
    <p class="report-muted"><b>Report time zone:</b> ${esc(timeZoneLabel(r))}. UTC is preserved in the underlying evidence.</p>
    ${section('At a glance',`<p>${esc(r.HumanSummary?.Headline)}</p><p>${esc(summary)}</p><div class="report-counts" aria-label="Finding counts">${counts}</div><p class="report-muted">Counts include measurements, connectivity, event findings and coverage checks. Healthy means no concern was detected by the available evidence.</p>`)}
    ${section('What needs attention',concerns.length?concerns.map(f=>`<div class="report-finding ${f.status.toLowerCase()}"><div class="report-finding-heading"><h3>${esc(f.label)}</h3>${badge(f.status)}</div><p>${esc(f.evidence)}</p><p class="report-next">Next step: ${esc(f.next)}</p><p class="report-muted">${esc(f.observationPeriod)}</p></div>`).join(''):'<p>No warning or critical findings were recorded. Missing evidence is listed under “Collection limits”.</p>')}
    ${section('Server measurements',table(['Indicator','Observed value','Assessment'],cards.filter(c=>!c.id.startsWith('storage-volume-')).map(c=>`<tr><td><b>${esc(c.label)}</b><p class="report-muted">${esc(c.evidence)}</p></td><td>${esc(value(c.value,c.units))}</td><td>${badge(c.status)}</td></tr>`))+`<p class="report-muted">${esc(cards[0]?.observationPeriod??'No measurement coverage recorded.')}</p>`)}
    ${Array.isArray(r.Measurements?.volumes)?section('Mounted drive capacities',volumeTable(r.Measurements,r.Rules)):''}
    ${live?section('Pending reboot',rebootDetails(r)):''}
    ${section('Connectivity',local?'<p>Not assessed. Network checks are not enabled for laptop mode; no DNS, ping, TCP, HTTPS or traceroute probes were sent.</p>':network(r))}`;
  if(r.Cluster)html+=section('Cluster availability',cluster(r));
  html+=section('System and Application error summary',local?'<p>Not assessed. Windows event collection is not enabled for laptop mode.</p>':events(r,interactive));
  html+=section('Collection limits',gapLines.length?list(gapLines):'<p>No collection errors, missing coverage or truncation were recorded for the enabled checks.</p>');
  html+=section('How to interpret this report',`<p>${esc(r.Interpretation)}</p><p>Thresholds are provisional and should be calibrated to the workload. Findings guide investigation and do not establish root cause.</p><details><summary>Assessment rules and measurement evidence</summary>${table(['Indicator','Applied rule','Observation period','Suggested investigation'],cards.map(c=>cells([c.label,c.rule,c.observationPeriod,c.next])))}</details>`);
  return html+`<div class="report-footer">Assessment ID: ${esc(r.AssessmentId)}<br>Schema: ${esc(r.SchemaVersion)} · Generated from the same preserved assessment as the technical export.</div></article>`;
}

function rebootDetails(r){
  const reboot=r.Measurements?.pendingReboot;
  if(!reboot)return '<p>Not assessed. This assessment has no pending reboot evidence. Run a new live assessment to include this check.</p>';
  const status=reboot.pending===true?'Warning':reboot.pending===false&&reboot.coverage==='Collected'?'Healthy':'Not Assessed';
  return `<p>${badge(status)} ${esc(reboot.pending===true?'A pending reboot indicator was detected.':status==='Healthy'?'No pending reboot indicators detected.':'Pending reboot status could not be fully assessed.')}</p><p class="report-muted">Checked: ${esc(formatTargetTime(reboot.checkedAtUtc,reportTimeZone(r)))} · Coverage: ${esc(reboot.coverage)}</p>`+
    table(['Windows indicator','Result','Registry evidence'],(reboot.indicators??[]).map(i=>cells([i.name,i.error?`Not assessed: ${i.error}`:i.pending===true?'Detected':i.pending===false?'Not detected':'Not assessed',`${i.registryPath}${i.valueName?' / '+i.valueName:''}`])))+
    `<p class="report-muted">${esc(reboot.scope)}</p><p>This assessment only reads these indicators. Coordinate any restart through your normal maintenance process.</p>`;
}

function network(r){
  const items=r.Connectivity??[],assessments=assessConnectivity(items);let index=0;
  if(!items.length)return '<p>Not assessed. No destinations were configured or collected.</p>';
  return table(['Destination','DNS','Ping','TCP / HTTP(S)','Assessment'],items.map(c=>{
    if(c.disabled)return cells([c.host,'Disabled','No probes','No probes','Not Assessed']);
    const f=assessments[index++];
    return `<tr><td><b>${esc(c.host)}</b><br>Port ${esc(c.port)}${c.trace?.attempted?`<p class="report-muted">Traceroute: ${c.trace.reached?'destination reached':'destination not reached'}${c.trace.truncated?' · incomplete':''}</p>`:''}${c.error?`<p>${esc(c.error)}</p>`:''}</td><td>${esc(c.dns?.resolvedAddress??c.dns?.error??'Not available')}</td><td>${esc(c.ping?`${c.ping.replies}/${c.ping.sent} replies; ${value(c.ping.averageMs,'ms average')}`:'Not assessed')}</td><td>${esc(c.tcp?.status??'Not Assessed')} / ${esc(c.https?.status??'Not Assessed')}<br>HTTP ${esc(c.https?.statusCode??'Not available')}</td><td>${badge(f.status)}</td></tr>`;
  }))+ '<p class="report-muted">DNS, ping, TCP and HTTP(S) are independent signals. Missing ping replies can reflect filtering; an HTTP error response still proves a response was received.</p>'+`<details><summary>Probe and path evidence</summary>${items.filter(c=>!c.disabled).map(c=>`<h3>${esc(c.host)} · ${esc(c.sourceServer)}</h3><p>TCP: ${esc(c.tcp?.error??c.tcp?.status)} · ${esc(value(c.tcp?.timingMs,'ms'))}<br>${esc((c.https?.protocol??'https').toUpperCase())}: ${esc(c.https?.error??c.https?.status)} · ${esc(value(c.https?.timingMs,'ms'))}</p><p>${esc(c.trace?.explanation??'Trace not assessed.')}</p>${c.trace?.attempted?table(['Hop','Address','Response time (ms)','State'],(c.trace.hops??[]).map(h=>cells([h.hop,h.address??'No response',(h.timingsMs??[]).join(', '),h.status??h.error??'Not available']))):''}`).join('')}</details>`;
}
function volumeTable(measurements,rules){
  const gib=bytes=>Number.isFinite(bytes)?`${(bytes/1073741824).toFixed(2)} GiB`:'Not available';
  const rows=measurements.volumes.map(v=>`<tr><td>${esc((v.mountPaths??[]).join(', ')||v.id)}${v.error?`<p>${esc(v.error)}</p>`:''}</td><td>${esc(v.label||'—')}</td><td>${esc(v.fileSystem||'Unknown')}</td><td>${gib(v.totalBytes)}</td><td>${gib(v.usedBytes)}</td><td>${gib(v.freeBytes)}</td><td>${Number.isFinite(v.freePercent)?esc(v.freePercent.toFixed(2)+'%'):'Not available'}</td><td>${badge(volumeStatus(v,rules))}</td></tr>`);
  return (rows.length?table(['Drive / mount paths','Label','File system','Total','Used','Free','Free %','Assessment'],rows):'<p>Not assessed. No mounted-volume capacity was returned.</p>')+`<p class="report-muted">One row per volume; multiple mount paths share the same capacity. GiB = 1,073,741,824 bytes. Capacity is a snapshot on the inspected target. Network mappings depend on the execution identity/session; unmounted partitions are excluded. Discovery: ${esc(measurements.volumeCapacityStatus??'Unknown')}. Storage latency covers the system drive only.</p>`;
}

function cluster(r){
  const c=r.Cluster;
  if(c.discoveryError)return `<p>Not assessed. ${esc(c.discoveryError)}</p>`;
  let html=`<p><b>${esc(c.name)}</b> ${badge(c.status)}</p><p>Quorum: ${esc(c.quorum?.configuration)} · Witness: ${esc(c.quorum?.witnessType)} ${badge(c.quorum?.status)}</p>${c.quorum?.fileSharePath?`<p>Witness share: ${esc(c.quorum.fileSharePath)}</p>`:''}<p>${esc(c.quorum?.evidence)}</p>`;
  html+=table(['Node','State','Collection'],(c.nodes??[]).map(n=>cells([n.name,n.state,n.error??n.collectionStatus])));
  html+=table(['Role or resource','Type','State','Owner'],[...(c.roles??[]).map(x=>({...x,type:'Role'})),...(c.resources??[])].map(x=>cells([x.name,x.type,x.state,x.owner])));
  const nodeCards=(r.Findings??[]).filter(f=>f.id.startsWith('node-'));
  if(nodeCards.length)html+=`<details><summary>Per-node measurements and gaps</summary>${table(['Indicator','Assessment','Evidence'],nodeCards.map(f=>`<tr><td>${esc(f.label)}</td><td>${badge(f.status)}</td><td>${esc(f.evidence)}</td></tr>`))}</details>`;
  if(c.recentErrors?.length)html+=list(c.recentErrors.map(e=>`Event ${e.eventId}: ${e.message}`));
  return html+`<p class="report-muted">${esc(c.workloadNote)}</p>`;
}
function events(r,interactive){
  if(!r.EnabledCapabilities?.events)return '<p>Not assessed. Event collection is not enabled for this assessment.</p>';
  const groups=reportErrorGroups(r),result=r.Collection?.EventResult;
  const zone=reportTimeZone(r),date=(value,event)=>formatTargetTime(value,zone,event);
  let html=`<p>Critical and Error entries grouped by log, source and Event ID. Warnings and informational events are included in investigation timelines.</p><p class="report-muted">${esc(date(result?.start))} to ${esc(date(result?.end))}. ${result?.groups?'Counts cover the scanned errors in this period.':'Counts cover the preserved sample only; run a new assessment for a full error scan.'} ${result?.truncated?'Scan limit reached; counts are partial.':''}</p>`;
  html+=groups.length?table(['Log','Source','Event ID','Error count','Most recent (target time)',...(interactive?['Occurrences']:[])],groups.map((g,index)=>`<tr><td>${esc(g.log)}</td><td>${esc(g.provider)}</td><td>${esc(g.eventId)}</td><td>${esc(g.count)}</td><td>${esc(date(g.lastSeen,g.latest))}</td>${interactive?`<td><button type="button" data-error-group="${index}">Select event ${esc(g.eventId)} — ${esc(g.provider)}</button></td>`:''}</tr>`),'event-summary-table'):'<p>No errors were returned. Review log coverage below before drawing conclusions.</p>';
  html+=table(['Computer','Log','Collection status','Count coverage'],(result?.searches??[]).map(c=>cells([c.node,c.log,c.error??c.status,c.status!=='Collected'?'Unavailable':c.truncated?'Partial — scan limit reached':result?.groups?'Complete for queried period':'Preserved sample'])),'event-coverage-table');
  html+='<p class="report-muted">Events provide context for investigation. Timing alone does not establish cause.</p>';
  for(const s of r.EventSearches??[]){html+=`<h3>Additional event search</h3><p>${esc(formatTargetTime(s.start,s.targetTimeZone??zone))} to ${esc(formatTargetTime(s.end,s.targetTimeZone??zone))} · ${esc((s.events??[]).length)} occurrences returned.${s.truncated?' Result cap reached.':''}</p>${table(['Computer','Log','Collection status'],(s.searches??[]).map(c=>cells([c.node,c.log,c.error??c.status])))}`;}
  for(const inv of r.EventInvestigations??[]){
    html+=`<details><summary>Investigation: event ${esc(inv.anchor.eventId)} · ${esc(inv.anchor.provider)} · ${esc(formatTargetTime(inv.anchor.timestamp,reportTimeZone(r,inv),inv.anchor))}</summary>${investigationBody(inv,r)}</details>`;
  }
  return html;
}

function eventDetail(e,selected=false,zone){return `<div class="report-timeline${selected?' selected-event':''}"><h3>Event ${esc(e.eventId)} · ${esc(e.provider)}${selected?' · Selected occurrence':''}</h3><p>${esc(formatTargetTime(e.timestamp,zone,e))} · ${esc(e.server)} / ${esc(e.log)} · ${esc(e.severity)} · Record ${esc(e.recordId)}</p><p class="event-message">${esc(e.message)}</p><details class="report-muted"><summary>Timestamp evidence (UTC / original)</summary><p>UTC: ${esc(e.timestamp)}<br>Original time: ${esc(e.originalTimestamp)} · ${esc(e.originalTimeZone)}</p></details></div>`;}
function investigationBody(inv,report){
  const zone=reportTimeZone(report,inv),date=value=>formatTargetTime(value,zone);
  return `<p class="report-muted"><b>Report time zone:</b> ${esc(timeZoneLabel(report,inv))}. UTC is preserved for event matching and timeline order.</p><p><b>Window:</b> ${esc(date(inv.window.start))} to ${esc(date(inv.window.end))} (±2 elapsed hours)</p><p>${esc(inv.timeline.length)} of ${inv.truncated?'at least ':''}${esc(inv.totalMatching)} matching events shown across all severities and Event IDs.${inv.truncated?' Result limit reached — this timeline is incomplete.':''}${inv.incompleteFollowUp?' The selected window extends beyond collection time; future events are not yet available.':''}</p><h3>Selected occurrence</h3>${eventDetail(inv.anchor,true,zone)}${table(['Computer','Log','Collection status'],(inv.searches??[]).map(c=>cells([c.node,c.log,c.error??c.status])))}${(inv.coverage??[]).length?list(inv.coverage.map(c=>`${c.scope}: ${c.reason}`)):''}<p class="report-note">${esc(inv.interpretation)} Collected: ${esc(date(inv.collectedAt))}.</p><h3>Timeline · oldest first (target time; ordered by UTC)</h3>${[...inv.timeline].sort((a,b)=>a.timestamp.localeCompare(b.timestamp)||String(a.key).localeCompare(String(b.key))).map(e=>eventDetail(e,e.key===inv.anchor.key,zone)).join('')||'<p>No timeline events were returned. Review collection status above.</p>'}`;
}
export function renderInvestigation(report,inv){return `<article class="report-document"><header class="report-heading"><div><div class="report-kicker">Ops Beacon 2.0 / Event investigation</div><h1>${esc(assessmentName(report))} · Event ${esc(inv.anchor.eventId)}</h1><p>${esc(inv.anchor.provider)} / ${esc(inv.anchor.log)} / Record ${esc(inv.anchor.recordId)}</p></div></header>${investigationBody(inv,report)}<div class="report-footer">Assessment ID: ${esc(report.AssessmentId)}<br>Investigation ID: ${esc(inv.id)} · Actual collection source: ${esc(report.Execution.actualSource)}</div></article>`;}
export function investigationExport(report,inv){return {SchemaVersion:report.SchemaVersion,AssessmentId:report.AssessmentId,Target:report.Target,DisplayName:assessmentName(report),Profile:report.Profile,Execution:report.Execution,TargetTimeZone:reportTimeZone(report,inv),Investigation:inv};}
export function investigationDocument(report,inv){return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ops Beacon event ${esc(inv.anchor.eventId)} — ${esc(assessmentName(report))}</title><style>${reportStyles}</style></head><body class="report-standalone"><div class="report-toolbar"><button onclick="window.print()">Print / Save as PDF</button></div>${renderInvestigation(report,inv)}</body></html>`;}
export function downloadFile(contents,type,name){const url=URL.createObjectURL(new Blob([contents],{type}));const a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),2000);}

export function reportDocument(report){
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ops Beacon assessment — ${esc(assessmentName(report))}</title><style>${reportStyles}</style></head><body class="report-standalone"><div class="report-toolbar"><button type="button" onclick="window.print()">Print / Save as PDF</button></div>${renderReport(report)}<script>window.addEventListener('beforeprint',${expandReportForPrint.toString()});</script></body></html>`;
}
export function downloadReadableReport(report){
  if(!report)return;
  const url=URL.createObjectURL(new Blob([reportDocument(report)],{type:'text/html;charset=utf-8'}));
  const link=document.createElement('a');link.href=url;link.download=`OpsBeacon-${report.AssessmentId}.html`;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
