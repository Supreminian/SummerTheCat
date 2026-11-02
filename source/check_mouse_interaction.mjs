import fs from 'node:fs';import path from 'node:path';import vm from 'node:vm';import assert from 'node:assert/strict';import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),config=JSON.parse(fs.readFileSync(path.join(root,'pet-pack/pet.json')));
// Raw-source regression baseline; v28 transitions/ranges have their own checks.
config.transitions={enabled:false};for(const a of Object.values(config.animations)){delete a.playbackRange;if(a.interactionOnly)a.holdLastFrameMs=300;}
const code=fs.readFileSync(path.join(root,'source/playback.js'),'utf8')+'\n'+fs.readFileSync(path.join(root,'source/mouse-interaction.js'),'utf8')+'\n({Playback:SummerPlayback,Mouse:SummerMouseInteraction})';const {Playback,Mouse}=vm.runInNewContext(code);
function fixture(){const p=new Playback(config);p.setRandomBehavior(false);p.setTailMode('moving');p.setState('natural_sit',true);p.markPresented();const m=new Mouse(p);m.setTeaserEnabled(true);return {p,m};}
function tick(f,ms){for(let time=0;time<ms;time+=1000/60){f.m.update(1000/60);f.p.advance(1000/60);f.p.markPresented();}}
function point(index,r=180){const angle=index*Math.PI/4;return [config.mouseInteraction.anchor[0]+Math.sin(angle)*r,config.mouseInteraction.anchor[1]-Math.cos(angle)*r];}
const directions=['up','up_right','right','down_right','down','down_left','left','up_left'],runs=[];
for(const [i,direction] of directions.entries()){
 const f=fixture();f.m.setPointer(...point(i));tick(f,100);assert.equal(f.p.state,'natural_sit','Reaction requires dwell');tick(f,120);assert.equal(f.p.state,'paw_'+direction);
 const seen=new Set([0]);let count=0;while(f.m.isPaw(f.p.state)){seen.add(f.p.frame);tick(f,1000/60);assert.ok(++count<500);}assert.equal(seen.size,config.animations['paw_'+direction].frames);tick(f,40);assert.ok(f.m.cooldownUntil>f.m.now);runs.push({direction,frames:seen.size,complete:true});
 tick(f,20_000);assert.equal(f.m.triggerCount,1,'Stationary mouse must not cause repeated swatting');
 f.m.setPointer(-500,-500);tick(f,200);f.m.setPointer(...point(i));tick(f,220);assert.equal(f.m.triggerCount,2,'Leaving and reapproaching rearms after cooldown');
}
// Teaser is the exclusive gate, even if mouse interaction is enabled.
for(const i of directions.keys()){
 const f=fixture();f.m.setTeaserEnabled(false);f.m.setEnabled(true);f.m.setPointer(...point(i));tick(f,1200);assert.equal(f.m.triggerCount,0,'Teaser off suppresses all eight directions');
 f.m.setTeaserEnabled(true);f.m.setPointer(...point(i));tick(f,220);assert.equal(f.m.triggerCount,1,'Teaser on restores direction');
 const state=f.p.state;f.m.setTeaserEnabled(false);assert.equal(f.p.state,state,'Switching off does not cut the current action');
 tick(f,20000);assert.equal(f.m.triggerCount,1,'Teaser off never rearms after current action');
}
const fresh=fixture();fresh.m=new Mouse(fresh.p);fresh.m.setEnabled(true);fresh.m.setPointer(...point(2));tick(fresh,1000);assert.equal(fresh.m.triggerCount,0,'New interaction defaults to teaser off');

// A complete resting image must remain presented for 300 ms, even after a RAF stall.
for(const state of directions.map(d=>'paw_'+d)){
 const f=fixture();f.p.setState(state,true);f.p.seek(config.animations[state].frames-1);f.p.markPresented();
 for(let t=0;t<290;t+=10){f.p.advance(10);f.p.markPresented();assert.equal(f.p.state,state);}
 f.p.advance(100);f.p.markPresented();assert.ok(f.p.isIdle(),'Rest hold eventually completes');
 const stalled=fixture();stalled.p.setState(state,true);stalled.p.advance(10_000);stalled.p.markPresented();stalled.p.advance(100);assert.equal(stalled.p.state,state,'A missed final frame still receives the full rest hold');
}
const busy=fixture();busy.p.setState('groom',true);busy.m.setPointer(...point(2));tick(busy,1000);assert.equal(busy.p.state,'groom');assert.equal(busy.m.triggerCount,0);busy.p.setState('natural_sit',true);busy.p.requestState('yawn');tick(busy,500);assert.equal(busy.m.triggerCount,0,'Native/manual menu queue takes priority');
const lock=fixture();lock.m.setPointer(...point(2));tick(lock,220);const extended=lock.p.state;lock.m.setPointer(...point(6));tick(lock,600);assert.equal(lock.p.state,extended);assert.equal(lock.m.triggerCount,1,'Direction locks for the full gesture');
const frozen=fixture();frozen.m.setPointer(...point(0));frozen.p.setPaused(true);tick(frozen,500);assert.equal(frozen.m.triggerCount,0);assert.equal(frozen.m.now,0);frozen.p.setPaused(false);frozen.m.setEnabled(false);tick(frozen,500);assert.equal(frozen.m.triggerCount,0);
const geometry=fixture();geometry.m.setPointer(...config.mouseInteraction.anchor);tick(geometry,1000);assert.equal(geometry.m.triggerCount,0,'Body center is a dead zone');geometry.m.setPointer(1000,1000);tick(geometry,1000);assert.equal(geometry.m.triggerCount,0,'Far mouse is ignored');
const jitter=fixture();const at=a=>[config.mouseInteraction.anchor[0]+Math.sin(a*Math.PI/180)*180,config.mouseInteraction.anchor[1]-Math.cos(a*Math.PI/180)*180];jitter.m.setPointer(...at(20));tick(jitter,40);assert.equal(jitter.m.candidate,'up');jitter.m.setPointer(...at(26));tick(jitter,40);assert.equal(jitter.m.candidate,'up','Sector hysteresis prevents boundary chatter');jitter.m.setPointer(...at(33));tick(jitter,40);assert.equal(jitter.m.candidate,'up_right');
const report={passed:true,teaserRequiredForAllEightDirections:true,teaserOffPreservesCurrentAction:true,teaserOffIsDefault:true,directionalRuns:runs,stationaryMouseTriggersOnce:true,exitAndReapproachRearms:true,busyActionsNotInterrupted:true,manualQueuePriority:true,gestureDirectionLocked:true,pauseAndDisableSuppressInteraction:true,bodyAndFarDeadZones:true,sectorHysteresis:true,fullStaticRestHold300ms:true,restHoldAfterRenderStall:true};fs.writeFileSync(path.join(root,'鼠标互动逻辑验证.json'),JSON.stringify(report,null,2));console.log('Eight direction mappings, complete frames, dwell, cooldown, manual priority and no interrupted limbs passed');
