import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {webcrypto} from 'node:crypto';
if(!globalThis.crypto)globalThis.crypto=webcrypto;
const nativeFetch=globalThis.fetch;
globalThis.fetch=(input,init)=>nativeFetch(typeof input==='string'&&input.startsWith('/')?`http://127.0.0.1:8080${input}`:input,init);
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const assets=path.join(root,'public','assets'),cache=new Map();
// Load browser ES modules without changing the portable application's module configuration.
function moduleUrl(file){
  if(cache.has(file))return cache.get(file);
  const source=fs.readFileSync(file,'utf8').replace(/from\s+(['"])(\.\/[^'"]+)\1/g,(_,quote,relative)=>`from '${moduleUrl(path.resolve(path.dirname(file),relative))}'`);
  const url=`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;cache.set(file,url);return url;
}
const {assessHealth}=await import(moduleUrl(path.join(assets,'assessment.js')));
const {createLiveReport}=await import(moduleUrl(path.join(assets,'live-report.js')));
const {renderReport,reportDocument}=await import(moduleUrl(path.join(assets,'report-view.js')));
const config=JSON.parse(fs.readFileSync(path.join(root,'config.json'),'utf8').replace(/^\uFEFF/,''));
const checks=[];function check(name,passed){checks.push({name,passed:Boolean(passed)});if(!passed)throw new Error(name);}
const options={os:'Windows',target:'TEST-SERVER',execution:'remote',profile:'General Purpose Server',events:false,sql:false,cluster:false,connectivity:false};
const volumes=[
  {id:'c',mountPaths:['C:\\'],label:'Windows',fileSystem:'NTFS',totalBytes:100*1073741824,freeBytes:40*1073741824,usedBytes:60*1073741824,freePercent:40},
  {id:'folder',mountPaths:['C:\\Data\\','D:\\Alias\\'],label:'Data <script>unsafe</script>',fileSystem:'ReFS',totalBytes:200*1073741824,freeBytes:0,usedBytes:200*1073741824,freePercent:0},
  {id:'empty',mountPaths:['E:\\'],label:'No media',totalBytes:null,freeBytes:null,usedBytes:null,freePercent:null,error:'No media'}
];
const m={localSnapshot:true,observationSeconds:5,cpu:10,memoryUsed:30,storageMs:1,volumes,volumeCapacityStatus:'Collected'};
const collection={ExecutionSource:'TEST-SERVER',Measurements:m,Errors:[],StartedAt:new Date().toISOString(),CompletedAt:new Date().toISOString()};
const r=createLiveReport(collection,options,config),cards=r.Health.Cards;
check('Each mounted volume gets an independent capacity assessment',cards.filter(c=>c.id.startsWith('storage-volume-')).length===3);
check('Full folder-mounted volume is Critical even with healthy C drive',cards.find(c=>c.id==='storage-volume-1').status==='Critical'&&cards.find(c=>c.id==='storage-volume-0').status==='Healthy');
check('Missing capacity is Not Assessed',cards.find(c=>c.id==='storage-volume-2').status==='Not Assessed');
const html=renderReport(r),standalone=reportDocument(r);
check('Readable report shows total used free and percentage table',html.includes('Mounted drive capacities')&&html.includes('Total</th>')&&html.includes('Used</th>')&&html.includes('Free %</th>')&&html.includes('200.00 GiB')&&html.includes('0.00%'));
check('All mount aliases and filesystem shown',html.includes('C:\\Data\\, D:\\Alias\\')&&html.includes('ReFS'));
check('Volume labels escaped',!html.includes('<script>unsafe</script>')&&html.includes('&lt;script&gt;unsafe&lt;/script&gt;'));
check('Standalone HTML and print/PDF include capacity table',standalone.includes('Mounted drive capacities')&&standalone.includes('200.00 GiB')&&standalone.includes('Print / Save as PDF')&&standalone.includes('@media print'));
check('JSON retains byte evidence for all volumes',JSON.parse(JSON.stringify(r)).Measurements.volumes.length===3&&r.Measurements.volumes[1].totalBytes===200*1073741824);
check('Partial discovery is a coverage gap',assessHealth({...m,volumeCapacityStatus:'Partial'},options,config.rules).some(c=>c.id==='storage-coverage'&&c.status==='Not Assessed'));
check('Empty discovery never becomes healthy capacity',assessHealth({...m,volumes:[]},options,config.rules).some(c=>c.id==='storage-coverage'&&c.status==='Not Assessed'));
const legacy={...m,diskFree:40,diskTotalGB:200,diskLabel:'C:'};delete legacy.volumes;
check('Older saved system-drive reports still assessed',assessHealth(legacy,options,config.rules).find(c=>c.id==='storage').status==='Healthy');
check('Cluster members receive per-volume capacity findings',(await import(moduleUrl(path.join(assets,'assessment.js')))).assessCluster({status:'Healthy',quorum:{status:'Healthy'},nodes:[{name:'NODE-2',measurements:m}],roles:[]},options,config.rules).some(c=>c.id==='node-0-storage-volume-1'&&c.status==='Critical'));
const live=JSON.parse(fs.readFileSync(path.join(root,'tests','volume-live-results.json'),'utf8').replace(/^\uFEFF/,''));
const real=createLiveReport(live,options,config);
check('Actual collected drives render in readable and standalone reports',live.Measurements.volumes.every(v=>renderReport(real).includes(v.mountPaths[0])&&reportDocument(real).includes(v.mountPaths[0])));
const {runChecks}=await import(moduleUrl(path.join(assets,'live-verification.js')));
const regression=await runChecks();checks.push(...regression);
if(regression.some(c=>!c.passed))throw new Error('Existing report regressions failed');
fs.writeFileSync(path.join(root,'tests','volume-report-results.json'),JSON.stringify(checks,null,2));
console.log(JSON.stringify(checks,null,2));
