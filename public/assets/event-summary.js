// Keep providers and logs separate: an Event ID alone does not identify a source.
export function errorGroups(events){
  const groups=new Map();
  for(const event of events??[]){
    if(!['System','Application'].includes(event.log)||!['Critical','Error'].includes(event.severity))continue;
    const key=JSON.stringify([event.server,event.log,event.provider,event.eventId]);
    let group=groups.get(key);
    if(!group){group={log:event.log,provider:event.provider,eventId:event.eventId,count:0,firstSeen:event.timestamp,lastSeen:event.timestamp,latest:event};groups.set(key,group);}
    group.count++;
    if(event.timestamp<group.firstSeen)group.firstSeen=event.timestamp;
    if(event.timestamp>group.lastSeen){group.lastSeen=event.timestamp;group.latest=event;}
  }
  return [...groups.values()].sort((a,b)=>a.log.localeCompare(b.log)||a.provider.localeCompare(b.provider)||a.eventId-b.eventId);
}
export const reportErrorGroups=report=>report.Collection?.EventResult?.groups??errorGroups(report.Events);
