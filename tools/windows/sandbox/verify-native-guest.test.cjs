'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {validateResume}=require('./verify-native-guest.cjs');
const factory={root:'D:\\owned\\factory',testRoot:'D:\\owned\\test'};
const previous={schema:1,syntheticOnly:true,passed:false,preconfiguredSyntheticSetupOnly:true,root:factory.testRoot,factory:factory.root,finished:'2026-11-18T02:00:00Z',hostPort:22001};
const profile={schema:1,profile:'node',ports:[{hostPort:22001,guestPort:8787}]};
test('owned resume keeps the exact synthetic root, fixed guest port and previous host mapping',()=>assert.doesNotThrow(()=>validateResume(previous,factory,profile)));
for(const [name,patch] of Object.entries({otherRoot:{root:'A:\\sandbox'},otherFactory:{factory:'A:\\sandbox'},realData:{syntheticOnly:false},successfulRun:{passed:true},unfinished:{finished:undefined},badDate:{finished:'not-a-date'},unconfigured:{preconfiguredSyntheticSetupOnly:false},reservedPort:{hostPort:18787},invalidPort:{hostPort:65536}}))
 test('resume refuses '+name,()=>assert.throws(()=>validateResume({...previous,...patch},factory,profile)));
test('resume refuses changed profile or port mapping',()=>{
 assert.throws(()=>validateResume(previous,factory,{...profile,profile:'sdk'}));
 assert.throws(()=>validateResume(previous,factory,{...profile,ports:[{hostPort:22002,guestPort:8787}]}));
 assert.throws(()=>validateResume(previous,factory,{...profile,ports:[{hostPort:22001,guestPort:8788}]}));
});
