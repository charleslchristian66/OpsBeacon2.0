import {formatTargetTime,reportTimeZone,timeZoneLabel} from './time-display.js';
import {renderReport,renderInvestigation,investigationDocument,investigationExport,reportDocument} from './report-view.js';
export function runTimeChecks(){
  const checks=[],check=(name,passed)=>checks.push({name,passed:Boolean(passed)});
  const zone={id:'Eastern Standard Time',periods:[
    {startUtc:'2026-01-01T00:00:00Z',endUtc:'2026-03-08T07:00:00Z',offsetMinutes:-300},
    {startUtc:'2026-03-08T07:00:00Z',endUtc:'2026-11-01T06:00:00Z',offsetMinutes:-240},
    {startUtc:'2026-11-01T06:00:00Z',endUtc:'2027-01-01T00:00:00Z',offsetMinutes:-300}]};
  const date=value=>formatTargetTime(value,zone);
  check('Target winter time crosses to the previous local calendar date',date('2026-11-17T03:46:12.0265066Z').includes('Nov 16, 2026, 10:46:12 PM')&&date('2026-11-17T03:46:12Z').includes('UTC−05:00'));
  check('Summer uses the historical daylight offset',date('2026-07-17T03:46:12Z').includes('Jul 16, 2026, 11:46:12 PM')&&date('2026-07-17T03:46:12Z').includes('UTC−04:00'));
  check('Spring transition has no fictitious 2 AM hour',date('2026-03-08T06:59:59Z').includes('1:59:59 AM')&&date('2026-03-08T07:00:00Z').includes('3:00:00 AM'));
  const first=date('2026-11-01T05:30:00Z'),second=date('2026-11-01T06:30:00Z');
  check('Repeated fall hour is distinguishable by offset',first.includes('1:30:00 AM')&&second.includes('1:30:00 AM')&&first.includes('UTC−04:00')&&second.includes('UTC−05:00'));
  const india={id:'India Standard Time',periods:[{startUtc:'2026-01-01T00:00:00Z',endUtc:'2027-01-01T00:00:00Z',offsetMinutes:330}]};
  check('Remote target half-hour offset works independently of browser zone',formatTargetTime('2026-11-17T03:46:12Z',india).includes('Nov 17, 2026, 9:16:12 AM (UTC+05:30)'));
  const legacy={timestamp:'2026-11-17T03:46:12Z',originalTimestamp:'2026-11-16T22:46:12-05:00',originalTimeZone:'Eastern Standard Time'};
  check('Older saved events retain their recorded local timestamp',formatTargetTime(legacy.timestamp,undefined,legacy).includes('10:46:12 PM (UTC−05:00)'));
  check('Unrelated original timestamp cannot supply a guessed offset',formatTargetTime('2026-07-17T03:46:12Z',undefined,legacy).includes('UTC (target-local time unavailable)'));
  check('Missing metadata and dates have explicit fallback',date('2001-01-01T00:00:00Z').includes('target-local time unavailable')&&formatTargetTime(null,zone)==='Not available'&&formatTargetTime('bad',zone)==='Not available');
  const event={...legacy,key:'anchor',recordId:1,server:'REMOTE',log:'System',provider:'Example',eventId:2,severity:'Error',message:'Evidence'};
  const report={Mode:'live',SchemaVersion:'2.0.0',AssessmentId:'test',Target:'REMOTE',Profile:'General Purpose Server',Options:{execution:'remote'},Execution:{actualSource:'REMOTE'},CompletedAt:event.timestamp,UpdatedAt:event.timestamp,Collection:{TargetTimeZone:zone,EventResult:{start:'2026-11-16T03:46:12Z',end:event.timestamp,groups:[{log:'System',provider:'Example',eventId:2,count:1,lastSeen:event.timestamp,latest:event}],searches:[]}},EnabledCapabilities:{events:true},Measurements:{},Health:{Cards:[]},Findings:[],Status:'Not Assessed',EventInvestigations:[]};
  const inv={id:'test',anchor:event,window:{start:'2026-11-17T01:46:12Z',end:'2026-11-17T05:46:12Z'},timeline:[event],searches:[],collectedAt:'2026-11-17T13:00:00Z',totalMatching:1};
  const before=JSON.stringify({report,inv}),html=renderReport(report),readable=renderInvestigation(report,inv);
  check('Assessment headings and grouped summary use target time',html.includes('Eastern Standard Time (inspected target)')&&html.includes('Most recent (target time)')&&html.includes('10:46:12 PM (UTC−05:00)')&&!html.includes('Most recent (UTC)'));
  check('Investigation bounds and collection time use target time',readable.includes('8:46:12 PM (UTC−05:00)')&&readable.includes('12:46:12 AM (UTC−05:00)')&&readable.includes('8:00:00 AM (UTC−05:00)'));
  check('Readable standalone exports retain local times and PDF controls',reportDocument(report).includes('10:46:12 PM (UTC−05:00)')&&investigationDocument(report,inv).includes('Print / Save as PDF')&&investigationDocument(report,inv).includes('8:46:12 PM (UTC−05:00)'));
  check('UTC evidence remains unchanged in rendering and JSON export',JSON.stringify({report,inv})===before&&investigationExport(report,inv).Investigation.anchor.timestamp===event.timestamp&&investigationExport(report,inv).TargetTimeZone===zone);
  check('Investigation metadata takes precedence over earlier assessment zone',reportTimeZone(report,{targetTimeZone:india})===india&&timeZoneLabel(report,{targetTimeZone:india}).includes('India Standard Time'));
  const fallback={...report,Collection:{EventResult:{groups:[{latest:event}]}}};
  check('Older report labels its recorded event zone and UTC fallback',timeZoneLabel(fallback).includes('recorded with events; other times use UTC'));
  const fallInv={...inv,anchor:{...event,timestamp:'2026-11-01T05:30:00Z'},timeline:[{...event,key:'second',timestamp:'2026-11-01T06:30:00Z'},{...event,key:'first',timestamp:'2026-11-01T05:30:00Z'}]};
  const fall=renderInvestigation(report,fallInv).split('Timeline · oldest first')[1];
  check('Fall-back timeline remains ordered by UTC across the repeated hour',fall.indexOf('UTC−04:00')<fall.indexOf('UTC−05:00'));
  return checks;
}
