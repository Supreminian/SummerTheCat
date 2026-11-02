import fs from 'node:fs';import path from 'node:path';import vm from 'node:vm';import assert from 'node:assert/strict';import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),config=JSON.parse(fs.readFileSync(path.join(root,'pet-pack/pet.json'))),Playback=vm.runInNewContext(fs.readFileSync(path.join(root,'source/playback.js'),'utf8')+'\nSummerPlayback');
// Raw-source regression baseline; v28 transitions/ranges have their own checks.
config.transitions={enabled:false};for(const a of Object.values(config.animations)){delete a.playbackRange;if(a.interactionOnly)a.holdLastFrameMs=300;}
let seed=1234567;const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
const p=new Playback(config,()=>{},random);assert.equal(p.randomBehavior,true);p.markPresented();
const counts={},visited=new Set([p.state]),runs=[];let frames=new Set([p.frame]),idleCycles=0,previousAuto=null;
for(let t=0;t<25*60*60;t++){
 const old=p.state,before=p.automaticActionCount;p.advance(1000/60);
 if(p.state!==old||p.frame===0&&p.elapsed<1000/p.animation.fps&&frames.has(p.config.animations[old].frames-1)){
  if(!p.isIdle(old)){assert.equal(frames.size,config.animations[old].frames,'Every original one-shot frame is presented');runs.push({state:old,frames:frames.size});}
  if(p.isIdle(old))idleCycles++;
  if(p.automaticActionCount>before){assert.ok(idleCycles>=2&&idleCycles<=5,'Random actions follow 2–5 complete idle cycles');assert.notEqual(p.state,previousAuto,'No consecutive identical random action');previousAuto=p.state;idleCycles=0;counts[p.state]=(counts[p.state]||0)+1;}
  frames=new Set();
 }
 frames.add(p.frame);visited.add(p.state);p.markPresented();
}
const scheduled=new Set([p.movingState,p.stillState,...config.randomBehavior.actions.map(a=>a.state)].filter(Boolean));
for(const id of scheduled)assert.ok(visited.has(id),'Random scheduler includes '+id);
for(const id of visited)assert.ok(scheduled.has(id),'Automatic behavior must not trigger an interactive, focus or conversation action '+id);
// Pause freezes both source playback and the random waiting interval.
p.setState('natural_sit',true);p.setPaused(true);const snapshot=[p.elapsed,p.behaviorCycles,p.automaticActionCount,p.pendingState];for(let i=0;i<300;i++)p.advance(1000/60);assert.deepEqual([p.elapsed,p.behaviorCycles,p.automaticActionCount,p.pendingState],snapshot);
// Manual requests win at the original boundary, even if an automatic event is due.
p.setPaused(false);p.behaviorCycles=1;p.requestState('groom');p.behaviorCycles=1;const count=p.automaticActionCount;while(p.isIdle()){p.advance(1000/60);p.markPresented();}assert.equal(p.state,'groom');assert.equal(p.automaticActionCount,count);
// Choosing another action during grooming must not interrupt grooming.
p.seek(40);p.markPresented();p.requestState('ears');assert.equal(p.state,'groom');assert.equal(p.pendingState,'ears');let guard=0;while(p.state==='groom'){p.advance(1000/60);p.markPresented();assert.ok(++guard<600);}assert.equal(p.state,'ears');
// Switching randomness off retains a user's pending action and tail settings.
p.requestState('look');p.setRandomBehavior(false);assert.equal(p.pendingState,'look');while(p.state==='ears'){p.advance(1000/60);p.markPresented();}assert.equal(p.state,'look');
while(!p.isIdle()){p.advance(1000/60);p.markPresented();}const disabledCount=p.automaticActionCount;for(let i=0;i<60*60;i++){p.advance(1000/60);p.markPresented();}assert.equal(p.automaticActionCount,disabledCount);
const report={passed:true,simulationMinutes:25,allSixStatesObserved:[...visited],automaticActionCounts:counts,completeOriginalFrameRuns:runs.length,idleCycleRange:[2,5],pauseFreezesScheduler:true,manualRequestPriority:true,manualRequestsDuringOneShotsWaitForCompletion:true,noImmediateRepeat:true,disablePreservesManualQueue:true};fs.writeFileSync(path.join(root,'随机行为验证.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
