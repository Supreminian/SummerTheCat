const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert');
const root=path.resolve(__dirname,'..');
const source=['playback.js','mouse-interaction.js','chat-motion.js'].map(n=>fs.readFileSync(path.join(__dirname,n),'utf8')).join('\n');
const api=vm.runInNewContext(source+'\n({SummerPlayback,SummerMouseInteraction,SummerChatMotion})');
const config=JSON.parse(fs.readFileSync(path.join(root,'pet-pack/pet.json'),'utf8'));
function make(){const p=new api.SummerPlayback(config,()=>{},()=>.5),i=new api.SummerMouseInteraction(p);p.setRandomBehavior(true);i.setEnabled(true);const c=new api.SummerChatMotion(p,i);return {p,i,c};}
function tick(p){p.markPresented();p.advance(1000/60);}
function until(p,predicate,max=3000){for(let n=0;n<max;n++){if(predicate())return;tick(p);}assert.fail('Playback condition timed out: '+p.state);}
const results=[];
for(const state of ['look','yawn','groom','ears','paw_up','evade_left']){
 const {p,c}=make();p.setState(state,true);p.seek(Math.min(20,p.endFrame-2));p.markPresented();const elapsed=p.elapsed;let finalSeen=false;
 c.begin();assert.equal(p.state,state);assert.equal(p.elapsed,elapsed);assert.equal(p.pendingState,'thinking_enter');
 until(p,()=>{if(p.state===state&&p.frame===p.endFrame)finalSeen=true;return p.state==='thinking_enter';});
 assert(finalSeen,'Original final frame skipped: '+state);assert.equal(c.phase,'entering');
 until(p,()=>p.state==='thinking_loop');assert.equal(c.phase,'listening');
 c.finish();assert.equal(p.state,'thinking_loop');assert.equal(p.pendingState,'thinking_exit');
 until(p,()=>p.state==='thinking_exit');until(p,()=>!c.active);assert(p.isIdle());
 results.push({action:state,completedBeforeThinking:true,exitAfterLoopBoundary:true});
}
{
 const {p,c,i}=make();p.setState('groom',true);p.seek(40);const elapsed=p.elapsed;c.begin();c.finish();
 assert.equal(p.state,'groom');assert.equal(p.elapsed,elapsed);assert.equal(p.pendingState,null);assert(!c.active);assert(p.randomBehavior&&i.enabled);
 results.push({case:'close before entry cancels only the queued entry',passed:true});
}
{
 const {p,c}=make();p.setState('thinking_enter',true);c.begin();p.seek(20);c.finish();assert.equal(p.state,'thinking_enter');assert.equal(p.pendingState,'thinking_exit');until(p,()=>p.state==='thinking_exit');
 c.begin();assert.equal(p.state,'thinking_exit');assert.equal(p.pendingState,'thinking_enter');until(p,()=>p.state==='thinking_enter');until(p,()=>p.state==='thinking_loop');
 const before=p.elapsed;until(p,()=>p.elapsed<before||p.elapsed>p.duration+500);assert.equal(p.state,'thinking_loop');assert(c.active);
 p.setPaused(true);const position=p.elapsed;for(let i=0;i<100;i++)tick(p);assert.equal(p.elapsed,position);p.setPaused(false);
 results.push({case:'rapid submit/reopen, sustained looping and pause',passed:true});
}
const report={passed:true,checks:results};fs.writeFileSync(path.join(root,'对话动作队列验证.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
