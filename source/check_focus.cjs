const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert');
const root=path.resolve(__dirname,'..'),config=JSON.parse(fs.readFileSync(path.join(root,'pet-pack/pet.json'))),context={};vm.createContext(context);vm.runInContext(fs.readFileSync(path.join(__dirname,'playback.js'),'utf8')+';this.Playback=SummerPlayback;',context);
const results=[];
for(const id of ['evade_left','evade_right']){
 const p=new context.Playback(config);p.setRandomBehavior(false);p.setState(id,true);let last=0,steps=0,joinCount=0;
 while(p.state===id&&steps++<1000){p.advance(1000/60);if(p.state!==id)break;assert(p.motionProgress>=last);last=p.motionProgress;if(p.transition?.kind==='frame-join')joinCount++;p.markPresented();if(steps===50){p.setPaused(true);const frozen=p.motionProgress;p.advance(1000);assert.equal(p.motionProgress,frozen);p.setPaused(false);}}
 assert(steps<1000);assert.equal(last,1);assert(p.isIdle());assert(joinCount>0);results.push({id,steps,joinCount,endsAtFullTravel:true,returnsToIdle:true});
}
assert(!config.randomBehavior?.actions?.some(a=>(typeof a==='string'?a:a.state||a.id||'').startsWith('evade_')));
fs.writeFileSync(path.join(root,'专心模式播放验证.json'),JSON.stringify({passed:true,results},null,2));console.log('Focus travel progress, pause, frame joins and sitting return passed');
