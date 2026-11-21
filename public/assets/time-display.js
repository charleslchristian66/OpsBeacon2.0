// UTC remains canonical. Offset periods come from TimeZoneInfo on the inspected target,
// including its DST setting; never infer a server's zone from the viewing browser.
const calendar=new Intl.DateTimeFormat('en-US',{dateStyle:'medium',timeStyle:'medium',timeZone:'UTC'});
export const reportTimeZone=(report,investigation)=>investigation?.targetTimeZone??report?.Collection?.TargetTimeZone??report?.Collection?.EventResult?.targetTimeZone;
export function timeZoneLabel(report,investigation){
  const zone=reportTimeZone(report,investigation);
  if(zone?.id)return `${zone.id} (inspected target)`;
  const event=investigation?.anchor??report?.Collection?.EventResult?.groups?.[0]?.latest??report?.Events?.[0];
  return event?.originalTimeZone?`${event.originalTimeZone} (recorded with events; other times use UTC)`:'Target time zone not recorded; UTC shown';
}
export function formatTargetTime(value,zone,event){
  if(!value)return 'Not available';
  const instant=new Date(value),utc=instant.getTime();
  if(!Number.isFinite(utc))return 'Not available';
  const period=zone?.periods?.find(p=>utc>=Date.parse(p.startUtc)&&utc<Date.parse(p.endUtc));
  let offset=period?.offsetMinutes;
  if(!Number.isFinite(offset)&&event?.originalTimeZone&&Date.parse(event.originalTimestamp)===utc){
    const match=event.originalTimestamp.match(/([+-])(\d{2}):(\d{2})$/);
    if(match)offset=(match[1]==='-'?-1:1)*(Number(match[2])*60+Number(match[3]));
    else if(event.originalTimestamp.endsWith('Z'))offset=0;
  }
  if(!Number.isFinite(offset))return calendar.format(instant)+' UTC (target-local time unavailable)';
  const absolute=Math.abs(offset),hours=String(Math.floor(absolute/60)).padStart(2,'0'),minutes=String(absolute%60).padStart(2,'0');
  return `${calendar.format(new Date(utc+offset*60000))} (UTC${offset<0?'−':'+'}${hours}:${minutes})`;
}
