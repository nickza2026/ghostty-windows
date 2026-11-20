'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {inputScript}=require('./native-window-input.cjs');
test('input script selects the visible terminal class, not first owned WGL/IME helper',()=>{
 const s=inputScript(1234,'owned ASCII ไทย');
 assert.match(s,/GetClassNameW/);assert.match(s,/localterm-dev\.window-prototype/);assert.match(s,/IsWindowVisible/);
 assert.match(s,/\$right\+64/);assert.match(s,/0x08000000/);assert.match(s,/HWND ownership changed/);
 assert.doesNotMatch(s,/SendInput|SetForegroundWindow|Clipboard/);
 assert(s.includes(Buffer.from('owned ASCII ไทย','utf8').toString('base64')));
});
test('input rejects invalid ownership or control/incomplete UTF-16 rather than executing arbitrary PS',()=>{
 for(const pid of [0,-1,NaN,1.5,0x100000000])assert.throws(()=>inputScript(pid,'fixture'));
 for(const line of ['line\nnext','\0','\x03','\x7f','\x85','\ud800','x'.repeat(3000)])assert.throws(()=>inputScript(1234,line));
});
test('branded fixture verifies actual HWND title before any password input',()=>{
 const s=inputScript(1234,'synthetic','Sandbox');
 assert.match(s,/GetWindowTextW/);
 assert.match(s,/Owned native title is not Sandbox/);
 assert(s.indexOf('Owned native title is not Sandbox')<s.indexOf('foreach($c'));
 assert.match(s,/verifiedSandboxTitle=\$titleText\.ToString\(\)/);
 assert.throws(()=>inputScript(1234,'synthetic',"Sandbox'; invoke-other"));
 assert.doesNotMatch(inputScript(1234,'synthetic'),/Owned native title is not Sandbox/);
});
