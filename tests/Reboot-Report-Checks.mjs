import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {webcrypto} from 'node:crypto';
if(!globalThis.crypto)globalThis.crypto=webcrypto;
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),cache=new Map();
function moduleUrl(file){
  if(cache.has(file))return cache.get(file);
  const source=fs.readFileSync(file,'utf8').replace(/from\s+(['"])(\.\/[^'"]+)\1/g,(_,q,relative)=>`from '${moduleUrl(path.resolve(path.dirname(file),relative))}'`);
  const url=`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;cache.set(file,url);return url;
}
const {createLiveReport}=await import(moduleUrl(path.join(root,'public/assets/live-report.js')));
const {renderReport,reportDocument}=await import(moduleUrl(path.join(root,'public/assets/report-view.js')));
const config=JSON.parse(fs.readFileSync(path.join(root,'config.json'),'utf8').replace(/^\uFEFF/,''));
const checks=[];function check(name,passed){checks.push({name,passed:Boolean(passed)});if(!passed)throw Error(name);}
const now=new Date().toISOString();
function make(reboot,profile='General Purpose Server'){
  return createLiveReport({ExecutionSource:'TARGET-SERVER',Measurements:{localSnapshot:true,observationSeconds:5,cpu:10,memoryUsed:30,diskFree:50,storageMs:1,pendingReboot:reboot},StartedAt:now,CompletedAt:now,Errors:[]},
    {target:'TARGET-SERVER',execution:'remote',os:'Windows',profile,events:false,sql:false,cluster:false,connectivity:false},config);
}
const pending={pending:true,status:'Warning',coverage:'Collected',checkedAtUtc:now,reasons:['Windows Update'],indicators:[{name:'Windows Update',pending:true,status:'Detected',registryPath:'HKLM\\test',valueName:null,error:null}],scope:'Windows registry reboot indicators'};
for(const profile of ['General Purpose Server','Database Server','Cluster Node']){
  const r=make(pending,profile),card=r.Health.Cards.find(c=>c.id==='pending-reboot');
  check(`${profile} includes a Warning with its reason`,card.status==='Warning'&&card.value==='Detected'&&card.evidence.includes('Windows Update'));
  check(`${profile} includes reboot in attention findings`,r.Findings.some(c=>c.id==='pending-reboot'&&c.status==='Warning'));
}
const clear={...pending,pending:false,status:'Healthy',reasons:[],indicators:pending.indicators.map(i=>({...i,pending:false,status:'Not detected'}))};
check('Clear complete evidence is Healthy',make(clear).Health.Cards.find(c=>c.id==='pending-reboot').status==='Healthy');
const denied={...clear,pending:null,status:'Not Assessed',coverage:'Partial',indicators:[{name:'Windows Update',pending:null,error:'Access <denied>',registryPath:'HKLM\\test'}]};
const deniedReport=make(denied);
check('Access gaps remain Not Assessed',deniedReport.Health.Cards.find(c=>c.id==='pending-reboot').status==='Not Assessed'&&deniedReport.MissingCoverage.some(g=>g.scope==='Pending reboot'));
check('Positive with a gap stays Warning',make({...pending,coverage:'Partial'}).Health.Cards.find(c=>c.id==='pending-reboot').status==='Warning');
check('Incomplete negative is never Healthy',make({...clear,coverage:'Partial'}).Health.Cards.find(c=>c.id==='pending-reboot').status==='Not Assessed');
const old=make(undefined);
check('Older assessments do not imply clear reboot status',old.Health.Cards.find(c=>c.id==='pending-reboot').status==='Not Assessed'&&renderReport(old).includes('no pending reboot evidence'));
const html=renderReport(make(pending)),download=reportDocument(make(pending));
check('Readable report includes reboot details and registry evidence',html.includes('<h2>Pending reboot</h2>')&&html.includes('HKLM\\test')&&html.includes('A pending reboot indicator was detected'));
check('Downloaded printable report includes same reboot evidence',download.includes('<h2>Pending reboot</h2>')&&download.includes('Windows Update')&&download.includes('window.print()'));
check('Registry errors are escaped in HTML',renderReport(deniedReport).includes('Access &lt;denied&gt;')&&!renderReport(deniedReport).includes('Access <denied>'));
check('Technical JSON preserves reboot evidence',JSON.parse(JSON.stringify(make(pending))).Measurements.pendingReboot.reasons[0]==='Windows Update');
const live=JSON.parse(fs.readFileSync(path.join(root,'tests/reboot-live-results.json'),'utf8').replace(/^\uFEFF/,''));
check('Actual target snapshot renders indicator table',renderReport(make(live)).includes('Component Based Servicing'));
console.log(`${checks.length}/${checks.length} pending reboot report checks passed`);
