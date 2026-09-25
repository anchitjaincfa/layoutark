import type {EstateReport,Lane,LayoutArkManifest,ManifestFile} from "./contracts";
export interface AnalysisOptions{recentDays?:number;archiveYears?:number;longPathThreshold?:number;sample?:boolean}
const DAY=86400000;
const age=(f:ManifestFile,ref:number)=>Math.max(0,Math.floor((ref-Date.parse(f.modifiedUtc))/DAY));
const folder=(f:ManifestFile)=>{const p=f.relPath.replace(/\\\\/g,"/").replace(/^\\/+|\\/+$/g,"").split("/").filter(Boolean);return p.length>1?`Root ${f.root}/${p[0]}`:`Root ${f.root}`};
export function analyzeManifest(m:LayoutArkManifest,o:AnalysisOptions={}):EstateReport{
 const ref=Date.parse(m.generatedAt);if(!Number.isFinite(ref))throw Error("manifest.generatedAt must be a valid date-time");
 const recent=o.recentDays??365,years=o.archiveYears??5,archive=Math.round(years*365.2425),limit=o.longPathThreshold??240;
 const groups=new Map<string,string[]>;m.files.forEach(f=>{const k=f.name.trim().toLocaleLowerCase("en-US")+"\0"+f.sizeBytes;groups.set(k,[...(groups.get(k)??[]),f.id])});
 const dup=new Set<string>;groups.forEach(ids=>{if(ids.length>1)ids.forEach(id=>dup.add(id))});
 const lanes:EstateReport["lanes"]={"convert-first":{count:0,rule:`Modified within ${recent} days of scan`,fileIds:[]},"convert-later":{count:0,rule:`Modified between ${recent+1} days and ${years} years before scan`,fileIds:[]},archive:{count:0,rule:`Not modified for at least ${years} years as of scan`,fileIds:[]}};
 const evidence:Record<string,string[]>={"cloud-only":[],"zero-byte":[],"long-path":[],"read-only":[],"possible-duplicate":[]};const folders=new Map<string,{count:number;bytes:number}>;let bytes=0,rec=0,cloud=0;
 const files=m.files.map(f=>{const days=age(f,ref),lane:Lane=days<=recent?"convert-first":days>=archive?"archive":"convert-later",flags:string[]=[];bytes+=f.sizeBytes;if(days<=recent)rec++;const flag=(id:string,test:boolean)=>{if(test){flags.push(id);evidence[id].push(f.id)}};flag("cloud-only",f.cloudState==="placeholder");if(f.cloudState==="placeholder")cloud++;flag("zero-byte",f.sizeBytes===0);flag("long-path",f.pathLength>limit);flag("read-only",f.readOnly);flag("possible-duplicate",dup.has(f.id));lanes[lane].count++;lanes[lane].fileIds.push(f.id);const k=folder(f),v=folders.get(k)??{count:0,bytes:0};v.count++;v.bytes+=f.sizeBytes;folders.set(k,v);return{...f,lane,flags}});
 const findings:EstateReport["findings"]=[],add=(ruleId:string,severity:"attention"|"warning"|"info",label:string,explanation:string)=>{if(evidence[ruleId].length)findings.push({ruleId,severity,label,explanation,evidenceFileIds:evidence[ruleId],guideUrl:"/guide#"+ruleId})};
 add("cloud-only","attention","Cloud-only placeholders","Download these files before attempting local conversion.");add("zero-byte","warning","Zero-byte files","Empty files may be damaged, incomplete, or intentional placeholders.");add("long-path","warning","Long paths",`Paths longer than ${limit} characters may fail in downstream tools.`);add("read-only","info","Read-only files","Conversion output may need a writable destination.");add("possible-duplicate","info","Possible duplicates","Files share a case-insensitive name and byte size; confirm contents before deleting.");
 if(!m.scan.complete||m.scan.errors.some(e=>e.count>0))findings.unshift({ruleId:"scan-incomplete",severity:"attention",label:"Scan may be incomplete",explanation:"Review scanner errors before relying on totals.",evidenceFileIds:[],guideUrl:"/guide#scan-incomplete"});
 const topFolders=[...folders].map(([folder,v])=>({folder,...v})).sort((a,b)=>b.bytes-a.bytes||b.count-a.count||a.folder.localeCompare(b.folder,"en-US")).slice(0,10);
 return{source:{hostLabel:m.host.hostLabel,generatedAt:m.generatedAt,complete:m.scan.complete,isSample:o.sample??false},totals:{files:files.length,bytes,recent:rec,cloudOnly:cloud,possibleDuplicates:dup.size},files,findings,lanes,topFolders};
}
export const analyzeEstate=analyzeManifest;
