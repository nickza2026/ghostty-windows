'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),{Screen}=require('./verify-letta-tui.cjs');
test('TUI diagnostic grid preserves painted positions and detects vertical one-column text',()=>{
 const wide=new Screen(129,41);wide.write('\x1b[2J\x1b[4;7HWelcome to Letta Code - ready for input\x1b[0m');assert.match(wide.text(),/Welcome to Letta Code - ready for input/);
 const vertical=new Screen(129,41);[...'Welcome to Letta Code'].forEach((ch,i)=>vertical.write(`\x1b[${i+1};1H${ch}`));assert.doesNotMatch(vertical.text(),/Welcome to Letta Code/);assert.ok(vertical.text().split('\n').every(l=>l.length<=1));
});
test('TUI diagnostic parser handles split VT strings, erase and overwrite rather than concatenating old text',()=>{
 const screen=new Screen(20,5);screen.write('\x1b[2;3Hold\x1b[');screen.write('2;3Hnew\x1b[K\x1b]0;ignored title\x07');assert.match(screen.text(),/new/);assert.doesNotMatch(screen.text(),/old|ignored/);screen.write('\x1b[2J');assert.equal(screen.text().trim(),'');
});
