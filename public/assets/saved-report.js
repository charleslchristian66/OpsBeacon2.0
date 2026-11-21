import {installReportStyles,renderReport,downloadReadableReport,assessmentName} from './report-view.js';
installReportStyles();
const content=document.getElementById('saved-assessment');
try{
  const id=new URLSearchParams(location.search).get('id');
  if(!/^[a-f0-9-]{36}$/.test(id??''))throw Error('This report link is invalid. Open a saved report from Ops Beacon.');
  const response=await fetch(`/api/reports/${id}`);
  if(!response.ok)throw Error(response.status===404?'This saved report could not be found.':'The report could not be loaded. Try again.');
  const report=await response.json();
  if(report.SchemaVersion!=='2.0.0'||!['live'].includes(report.Mode))throw Error('This report format is not supported.');
  document.title=`Ops Beacon assessment — ${assessmentName(report)}`;
  content.innerHTML=renderReport(report);
  for(const inv of report.EventInvestigations??[]){
    const link=document.createElement('a');link.href=`/assets/investigation.html?id=${encodeURIComponent(report.AssessmentId)}&investigation=${encodeURIComponent(inv.id)}`;link.textContent=`Event ${inv.anchor.eventId} investigation · JSON / Print to PDF`;document.querySelector('.report-toolbar').append(link);
  }
  document.getElementById('saved-print').disabled=false;document.getElementById('saved-print').onclick=()=>window.print();
  document.getElementById('saved-download').disabled=false;document.getElementById('saved-download').onclick=()=>downloadReadableReport(report);
}catch(error){content.textContent=error.message;content.setAttribute('role','alert');}
