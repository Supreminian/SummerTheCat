// Conversation owns a queue, never the current clip's playback position.
class SummerChatMotion {
 constructor(playback,interaction,onChange=()=>{}) {
  this.playback=playback;this.interaction=interaction;this.onChange=onChange;
  this.phase='idle';this.desired=false;this.saved=null;this.mutating=false;
  const previous=playback.onChange;
  playback.onChange=value=>{previous(value);if(!this.mutating)this.sync();};
 }
 get active(){return this.phase!=='idle';}
 emit(){this.onChange({phase:this.phase,active:this.active,desired:this.desired,state:this.playback.state,pending:this.playback.pendingState});}
 begin(){
  const p=this.playback;
  if(!p.config.animations.thinking_enter)return false;
  this.desired=true;
  if(!this.active){
   this.saved={random:p.randomBehavior,interaction:this.interaction.enabled};
   this.phase='waiting';this.mutating=true;
   p.setRandomBehavior(false);this.interaction.setEnabled(false);this.mutating=false;
  }
  if(!['thinking_enter','thinking_loop'].includes(p.state))p.requestState('thinking_enter');
  else if(p.pendingState==='thinking_exit')p.clearPending();
  this.sync();return true;
 }
 finish(){
  this.desired=false;const p=this.playback;
  if(this.phase==='waiting'&&!p.state.startsWith('thinking_')){
   if(p.pendingState==='thinking_enter')p.clearPending();
   this.release();return;
  }
  if(['thinking_enter','thinking_loop'].includes(p.state))p.requestState('thinking_exit');
  this.sync();
 }
 release(){
  const saved=this.saved;this.saved=null;this.phase='idle';this.desired=false;
  this.mutating=true;
  if(saved){this.playback.setRandomBehavior(saved.random);this.interaction.setEnabled(saved.interaction);}
  this.mutating=false;this.emit();
 }
 sync(){
  if(!this.active)return;
  const p=this.playback;
  if(p.state==='thinking_enter')this.phase='entering';
  else if(p.state==='thinking_loop')this.phase='listening';
  else if(p.state==='thinking_exit')this.phase='returning';
  else if(!this.desired){this.release();return;}
  else this.phase='waiting';
  if(!this.desired&&['thinking_enter','thinking_loop'].includes(p.state)&&p.pendingState!=='thinking_exit')p.requestState('thinking_exit');
  this.emit();
 }
}
