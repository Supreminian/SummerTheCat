import fs from 'node:fs';import path from 'node:path';import vm from 'node:vm';import assert from 'node:assert/strict';import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),config=JSON.parse(fs.readFileSync(path.join(root,'pet-pack/pet.json')));const Playback=vm.runInNewContext(fs.readFileSync(path.join(root,'source/playback.js'),'utf8')+'\nSummerPlayback');
function fixture(){const p=new Playback(config);p.setRandomBehavior(false);p.setTailMode('moving');p.setState('natural_sit',true);p.markPresented();return p;}
const runs=[];
for(const [id,a] of Object.entries(config.animations)){
 if(a.loop)continue;
 const p=fixture();p.setState(id,true);assert(p.transition);const first=p.frame;p.advance(80);assert.equal(p.frame,first);assert.equal(p.elapsed,0);const frozen=p.transition.elapsed;p.setPaused(true);p.advance(1000);assert.equal(p.transition.elapsed,frozen);p.setPaused(false);
 const seen=new Set();let ticks=0;while(p.state===id){if(!p.transition){seen.add(p.frame);p.markPresented();}p.advance(1000/60);assert(++ticks<1000);}
 const start=a.playbackRange?.startFrame||0,end=(a.playbackRange?.endFrameExclusive||a.frames)-1;assert.equal(seen.size,end-start+1);assert(seen.has(start)&&seen.has(end));assert(p.isIdle());assert.equal(p.transition.fromState,id);assert.equal(p.transition.fromFrame,end);runs.push({state:id,sourceFrames:a.frames,playedFrames:seen.size,firstFrame:start,lastFrame:end,completeReturnToIdle:true});
}
const queued=fixture();queued.setState('groom',true);queued.requestState('yawn');const boundary=queued.boundary;queued.setPaused(true);queued.advance(1000);assert.equal(queued.boundary,boundary);queued.setPaused(false);let n=0;while(queued.state==='groom'){queued.advance(1000/60);queued.markPresented();assert(++n<1000);}assert.equal(queued.state,'yawn');assert.equal(queued.transition.fromState,'groom');
const seek=fixture();seek.setState('look',true);seek.seek(40);assert.equal(seek.transition,null);assert.equal(seek.frame,40);
const trim=JSON.parse(fs.readFileSync(path.join(root,'衔接与静坐裁剪记录.json')));assert(trim.ranges.filter(a=>a.state.startsWith('paw_')).every(a=>a.totalReturnRestMs>=300));
fs.writeFileSync(path.join(root,'过渡状态机验证.json'),JSON.stringify({passed:true,runs,transitionFreezesDestinationClock:true,pauseFreezesTransition:true,manualQueueSurvivesTransition:true,seekCancelsTransition:true,allPawsRestAtLeast300ms:true},null,2));console.log('Transitions, retained frame ranges, pause, queues and 300 ms paw rest passed');
