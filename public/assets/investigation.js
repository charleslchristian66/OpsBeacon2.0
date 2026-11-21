import {installReportStyles,renderInvestigation,investigationExport,investigationDocument,downloadFile,assessmentName} from './report-view.js';
installReportStyles();
const $=id=>document.getElementById(id);
try{
  const params=new URLSearchParams(location.search),id=params.get('id'),investigation=params.get('investigation');
  if(![id,investigation].every(value=>/^[a-f0-9-]{36}$/.test(value??'')))throw Error('Invalid event investigation link. Open an investigation from its assessment.');
  const response=await fetch(`/api/reports/${id}`);if(!response.ok)throw Error('The saved assessment could not be loaded.');
  const report=await response.json();if(report.Mode!=='live'||report.SchemaVersion!=='2.0.0')throw Error('Unsupported assessment format.');
  const inv=report.EventInvestigations?.find(item=>item.id===investigation);if(!inv)throw Error('This investigation was not found in the saved assessment.');
  $('content').innerHTML=renderInvestigation(report,inv);document.title=`Ops Beacon — ${assessmentName(report)} — Event ${inv.anchor.eventId}`;
  for(const name of ['print','html','json'])$(name).disabled=false;
  $('print').onclick=()=>window.print();
  $('html').onclick=()=>downloadFile(investigationDocument(report,inv),'text/html;charset=utf-8',`OpsBeacon-Event-${inv.anchor.eventId}-${inv.id}.html`);
  $('json').onclick=()=>downloadFile(JSON.stringify(investigationExport(report,inv),null,2),'application/json',`OpsBeacon-Event-${inv.anchor.eventId}-${inv.id}.json`);
}catch(error){$('content').textContent=error.message;$('content').setAttribute('role','alert');}
