import type {EstateReport} from "./contracts";
const D=/^[\\t\\r ]*[=+\\-@]/;
export const defendCsvFormula=(v:string)=>D.test(v)?"'"+v:v;
export function csvCell(v:string|number|boolean){const s=defendCsvFormula(String(v));return /[",\\r\\n]/.test(s)?'"'+s.replace(/"/g,'""')+'"':s}
export function exportWorklistCsv(r:EstateReport){const h=["id","root","relative_path","name","size_bytes","modified_utc","cloud_state","read_only","path_length","lane","flags"],rows=r.files.map(f=>[f.id,f.root,f.relPath,f.name,f.sizeBytes,f.modifiedUtc,f.cloudState,f.readOnly,f.pathLength,f.lane,f.flags.join("|")].map(csvCell).join(","));return[h.join(","),...rows].join("\\r\\n")+"\\r\\n"}
export const reportToCsv=exportWorklistCsv;
