// Original, complete video frames. Tail control chooses an entire seated clip.
class SummerPlayback {
 constructor(config,onChange=()=>{},random=Math.random){
  this.config=config;this.onChange=onChange;this.random=random;this.state=config.defaultState;this.elapsed=0;this.motionElapsed=0;this.paused=false;this.pendingState=null;this.boundary=null;this.waitingFinal=false;this.transition=null;this.handledJoins=new Set();this.presentedState=null;this.presentedFrame=-1;this.presentedMs=0;
  this.movingState=config.tailControl?.movingState||config.defaultState;this.stillState=config.tailControl?.stillState;
  this.tailMode=config.tailControl?.defaultMode||'moving';this.idleChoice=this.movingState;this.randomCycles=this.sampleCycles();
  this.behavior=config.randomBehavior||{};this.randomBehavior=Boolean(this.behavior.enabled);this.lastAutomaticAction=null;this.automaticActionCount=0;this.behaviorCycles=this.randomBehavior?this.sampleBehaviorCycles():null;
 }
 get animation(){return this.config.animations[this.state];}
 get startFrame(){return this.animation.playbackRange?.startFrame||0;}
 get endFrame(){return (this.animation.playbackRange?.endFrameExclusive||this.animation.frames)-1;}
 get frameCount(){return this.endFrame-this.startFrame+1;}
 get duration(){return this.frameCount*1000/this.animation.fps+(this.animation.loop?0:this.animation.holdLastFrameMs||0);}
 get position(){const p=this.elapsed*this.animation.fps/1000;return this.startFrame+(this.animation.loop?p%this.frameCount:Math.min(this.frameCount-1,p));}
 get frame(){return Math.floor(this.position);}
 get motionProgress(){const m=this.animation.evadeMotion;if(!m)return 0;const ms=1000/this.animation.fps,start=m.startFrame*ms,end=m.endFrame*ms+(this.animation.frameTransitions||[]).filter(j=>j.frame<=m.endFrame).reduce((s,j)=>s+(j.durationMs||100),0);return Math.max(0,Math.min(1,(this.motionElapsed-start)/Math.max(1,end-start)));}
 isIdle(id=this.state){return id===this.movingState||id===this.stillState;}
 get idleState(){return this.tailMode==='still'?this.stillState:this.tailMode==='moving'?this.movingState:this.idleChoice;}
 sampleCycles(){const min=this.config.tailControl?.minimumCycles||1,max=this.config.tailControl?.maximumCycles||3;return min+Math.min(max-min,Math.floor(this.random()*(max-min+1)));}
 sampleBehaviorCycles(){const min=this.behavior.minimumIdleCycles||2,max=this.behavior.maximumIdleCycles||5;return min+Math.min(max-min,Math.floor(this.random()*(max-min+1)));}
 resetBehaviorWait(){this.behaviorCycles=this.randomBehavior?this.sampleBehaviorCycles():null;}
 setRandomBehavior(value){this.randomBehavior=Boolean(value);this.resetBehaviorWait();this.emit();return true;}
 pickBehaviorAction(){
  let choices=(this.behavior.actions||[]).filter(a=>this.config.animations[a.state]&&!this.isIdle(a.state)&&!this.config.animations[a.state].loop&&Number.isFinite(a.weight)&&a.weight>0);
  if(this.behavior.avoidImmediateRepeat&&choices.length>1)choices=choices.filter(a=>a.state!==this.lastAutomaticAction);
  if(!choices.length)return null;let value=this.random()*choices.reduce((sum,a)=>sum+a.weight,0);
  const chosen=choices.find(a=>(value-=a.weight)<0)||choices.at(-1);this.lastAutomaticAction=chosen.state;this.automaticActionCount++;return chosen.state;
 }
 emit(){this.onChange({state:this.state,pending:this.pendingState,tailMode:this.tailMode,randomBehavior:this.randomBehavior});}
 clearPending(){this.pendingState=null;this.boundary=null;this.waitingFinal=false;}
 setState(id,restart=false,preserveBehaviorWait=false){
  if(!this.config.animations[id])return false;
  const oldState=this.state,oldFrame=this.presentedState===oldState?this.presentedFrame:this.frame,shown=this.presentedState===oldState;
  this.clearPending();if(!preserveBehaviorWait)this.resetBehaviorWait();
  if(id!==this.state||restart){
   this.state=id;this.elapsed=0;this.motionElapsed=0;this.handledJoins.clear();this.presentedState=null;this.presentedFrame=-1;this.presentedMs=0;this.transition=null;
   const policy=this.config.transitions;
   if(policy?.enabled&&shown){const durationMs=oldState===id&&preserveBehaviorWait?(policy.loopDurationMs||90):(policy.durationMs||160);this.transition={fromState:oldState,fromFrame:oldFrame,elapsed:0,durationMs};}
  }
  this.emit();return true;
 }

 queue(id){if(this.pendingState!==id){this.pendingState=id;this.boundary=(Math.floor(this.elapsed/this.duration)+1)*this.duration;this.waitingFinal=false;this.emit();}return true;}
 requestState(id){
  if(!this.config.animations[id])return false;
  if(id===this.movingState)id=this.idleState;
  this.resetBehaviorWait();
  // Every manual choice respects the current complete clip, including an
  // automatically selected action. Choosing the current state cancels a queue.
  if(id!==this.state)return this.queue(id);
  this.clearPending();this.emit();return true;
 }
 setTailMode(mode){
  if(!this.stillState||!['random','moving','still'].includes(mode))return false;
  if(mode===this.tailMode)return true;
  this.tailMode=mode;
  if(mode==='random'){if(this.isIdle())this.idleChoice=this.state;this.randomCycles=this.sampleCycles();}
  // A queued action retains priority and the original current-cycle boundary.
  if(this.isIdle()&&(!this.pendingState||this.isIdle(this.pendingState))){
   if(this.idleState!==this.state)this.queue(this.idleState);else this.clearPending();
  }
  this.emit();return true;
 }
 setPaused(value){this.paused=Boolean(value);}
 seek(frame){this.clearPending();this.transition=null;this.handledJoins.clear();this.elapsed=(Math.max(this.startFrame,Math.min(this.endFrame,frame))-this.startFrame)*1000/this.animation.fps;this.motionElapsed=this.elapsed+(this.animation.frameTransitions||[]).filter(j=>j.frame<=this.frame).reduce((s,j)=>s+(j.durationMs||100),0);this.presentedState=null;this.presentedFrame=-1;this.presentedMs=0;this.emit();}
 markPresented(){if(this.transition)return;if(this.presentedState!==this.state||this.presentedFrame!==this.frame){this.presentedState=this.state;this.presentedFrame=this.frame;this.presentedMs=0;}}
 nextIdle(){
  if(this.tailMode==='random'&&this.stillState){
   if(--this.randomCycles<=0){this.idleChoice=this.idleChoice===this.movingState?this.stillState:this.movingState;this.randomCycles=this.sampleCycles();}
  }
  return this.idleState;
 }
 advance(dt){
  if(this.paused||!Number.isFinite(dt)||dt<=0)return;
  if(this.animation.evadeMotion&&(!this.transition||this.transition.kind==='frame-join'))this.motionElapsed+=dt;
  if(this.transition){
   this.transition.elapsed+=dt;if(this.transition.elapsed<this.transition.durationMs)return;
   dt=Math.min(Math.max(0,this.transition.elapsed-this.transition.durationMs),1000/this.animation.fps-.00001);this.transition=null;if(dt<=0)return;
  }
  if(this.presentedState===this.state&&this.presentedFrame===this.endFrame)this.presentedMs+=dt;
  const frameMs=1000/this.animation.fps;
  const end=this.pendingState?this.boundary:((this.isIdle()||this.animation.conversationLoop)?(Math.floor(this.elapsed/this.duration)+1)*this.duration:(!this.animation.loop?this.duration:null));
  const oldFrame=this.frame;this.elapsed+=dt;
  const join=(this.animation.frameTransitions||[]).find(j=>!this.handledJoins.has(j.frame)&&oldFrame<j.frame&&this.frame>=j.frame);
  if(join){this.handledJoins.add(join.frame);this.elapsed=(join.frame-this.startFrame)*frameMs;this.transition={kind:'frame-join',fromState:this.state,fromFrame:this.presentedState===this.state?this.presentedFrame:oldFrame,elapsed:0,durationMs:join.durationMs||100};return;}
  if(end!==null&&this.elapsed>=end){
   const finalSeen=this.presentedState===this.state&&this.presentedFrame===this.endFrame;
   // Normal playback follows the clip's scheduled boundary. Do not add an
   // extra last-frame hold or discard fractional RAF time at every cycle.
   // Only recover a genuinely missed final frame after a long rendering stall.
   const restHold=this.animation.loop?0:(this.animation.holdLastFrameMs||0);
   if(finalSeen&&this.presentedMs>=restHold&&(!this.waitingFinal||this.presentedMs>=frameMs+restHold)){
    const remainder=this.waitingFinal?0:Math.max(0,this.elapsed-end);
    let next=this.pendingState;
    if(next)this.resetBehaviorWait();
    else if(this.isIdle()){
     next=this.nextIdle();
     if(this.randomBehavior&&--this.behaviorCycles<=0){next=this.pickBehaviorAction()||next;this.resetBehaviorWait();}
    }else if(this.animation.conversationLoop){next=this.state;}else{next=this.animation.restState===this.movingState?this.idleState:this.animation.restState||this.config.defaultState;this.resetBehaviorWait();}
    this.setState(next,true,true);
    // Carry normal refresh quantization into the next clip, while keeping its
    // first original frame visible even after an exceptional long stall.
    this.elapsed=Math.min(remainder,1000/this.animation.fps-.00001);
   }else{this.elapsed=end-.00001;this.waitingFinal=true;}
  }
 }
}
