import {strict as assert} from "node:assert";
import {analyzeManifest,defendCsvFormula,exportWorklistCsv,validateManifest} from "../../src/core/index";
import type {LayoutArkManifest} from "../../src/core/contracts";
const m:LayoutArkManifest={schema:"layoutark.manifest",version:1,generator:{name:"layoutark-scan",version:"1"},generatedAt:"2026-09-24T12:00:00Z",host:{psEdition:"Desktop",psVersion:"7",os:"Windows",hostLabel:"host",publisher:{detected:"yes",version:"2019",via:"registry"}},roots:[{index:0,path:"C:\\Docs",kind:"custom"}],scan:{startedAt:"2026-09-24T11:00:00Z",finishedAt:"2026-09-24T12:00:00Z",complete:false,fileCount:4,errors:[],redaction:"none"},files:[
{id:"a",root:0,relPath:"Current\\Budget.pub",name:"=Budget.pub",sizeBytes:100,modifiedUtc:"2026-09-01T00:00:00Z",createdUtc:"2020-01-01T00:00:00Z",cloudState:"placeholder",readOnly:true,pathLength:250},
{id:"b",root:0,relPath:"Old\\Budget.pub",name:"=budget.pub",sizeBytes:100,modifiedUtc:"2010-01-01T00:00:00Z",createdUtc:"2010-01-01T00:00:00Z",cloudState:"local",readOnly:false,pathLength:30},
{id:"c",root:0,relPath:"Middle\\Flyer.pub",name:"Flyer.pub",sizeBytes:10,modifiedUtc:"2023-01-01T00:00:00Z",createdUtc:"2023-01-01T00:00:00Z",cloudState:"unknown",readOnly:false,pathLength:30},
{id:"d",root:0,relPath:"Middle\\Empty.pub",name:"Empty.pub",sizeBytes:0,modifiedUtc:"2023-01-01T00:00:00Z",createdUtc:"2023-01-01T00:00:00Z",cloudState:"local",readOnly:false,pathLength:30}]};
assert.equal(validateManifest(m).ok,true);
assert.equal(validateManifest({...m,scan:{...m.scan,fileCount:3}}).ok,false);
const r=analyzeManifest(m);assert.deepEqual(r.totals,{files:4,bytes:210,recent:1,cloudOnly:1,possibleDuplicates:2});
assert.deepEqual(r.files.map(f=>f.lane),["convert-first","archive","convert-later","convert-later"]);
assert.deepEqual(r.findings.map(f=>f.ruleId),["scan-incomplete","cloud-only","zero-byte","long-path","read-only","possible-duplicate"]);
assert.equal(defendCsvFormula(" =SUM(A1:A2)"),"' =SUM(A1:A2)");assert.match(exportWorklistCsv(r),/'=Budget\.pub/);
console.log("core tests passed");
