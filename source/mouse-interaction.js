// Select an intact recorded gesture; never deform, mirror or assemble pixels.
class SummerMouseInteraction {
 constructor(playback,onTrigger=()=>{}){
  this.playback=playback;this.policy=playback.config.mouseInteraction||{};this.enabled=Boolean(this.policy.enabled);this.teaserEnabled=false;this.onTrigger=onTrigger;
  this.directions=['up','up_right','right','down_right','down','down_left','left','up_left'];
  this.pointer=null;this.now=0;this.candidate=null;this.dwell=0;this.outside=0;this.latched=false;this.lastTriggerPoint=null;this.cooldownUntil=0;this.previousState=playback.state;this.triggerCount=0;
 }
 setTeaserEnabled(value){this.teaserEnabled=Boolean(value);this.clearPointer();this.latched=false;this.lastTriggerPoint=null;return this.teaserEnabled;}
 setEnabled(value){this.enabled=Boolean(value);this.clearPointer();return this.enabled;}
 setPointer(x,y,active=true){this.pointer=active&&Number.isFinite(x)&&Number.isFinite(y)?{x,y}:null;}
 clearPointer(){this.pointer=null;this.candidate=null;this.dwell=0;}
 suspend(ms=500){this.clearPointer();this.cooldownUntil=Math.max(this.cooldownUntil,this.now+ms);}
 isPaw(state){return Object.values(this.policy.directions||{}).includes(state);}
 target(){
  if(!this.pointer)return {direction:null,ratio:Infinity};
  const [cx,cy]=this.policy.anchor||[288,258],[rx,ry]=this.policy.reach||[260,280],dx=this.pointer.x-cx,dy=this.pointer.y-cy;
  const ratio=Math.hypot(dx/rx,dy/ry);if(ratio>1||Math.hypot(dx,dy)<(this.policy.innerRadius||42))return {direction:null,ratio};
  const angle=(Math.atan2(dx,-dy)*180/Math.PI+360)%360;let sector=Math.floor((angle+22.5)/45)%8;
  if(this.candidate){const old=this.directions.indexOf(this.candidate),distance=Math.abs(((angle-old*45+540)%360)-180);if(distance<=22.5+(this.policy.sectorHysteresisDegrees||7))sector=old;}
  return {direction:this.directions[sector],ratio};
 }
 update(dt){
  if(!Number.isFinite(dt)||dt<=0)return;
  if(this.playback.paused){this.candidate=null;this.dwell=0;return;}
  this.now+=dt;
  const state=this.playback.state;
  if(this.isPaw(this.previousState)&&state!==this.previousState){this.cooldownUntil=Math.max(this.cooldownUntil,this.now+(this.policy.cooldownMs||1800));this.candidate=null;this.dwell=0;}
  this.previousState=state;
  const target=this.target();
  if(!this.teaserEnabled||!this.enabled||target.ratio>(this.policy.exitRatio||1.15)){
   this.outside+=dt;if(this.outside>=(this.policy.exitDwellMs||160)){this.latched=false;this.lastTriggerPoint=null;}
   this.candidate=null;this.dwell=0;return;
  }
  this.outside=0;
  // Leave a busy cat alone; do not enqueue stale mouse targets behind a yawn,
  // grooming action, menu request, or an already extended paw.
  if(!target.direction||!this.playback.isIdle()||this.playback.transition||this.playback.pendingState||this.now<this.cooldownUntil){this.candidate=null;this.dwell=0;return;}
  if(this.latched&&this.lastTriggerPoint){
   if(Math.hypot(this.pointer.x-this.lastTriggerPoint.x,this.pointer.y-this.lastTriggerPoint.y)<(this.policy.rearmMovement||48)){this.candidate=null;this.dwell=0;return;}
   this.latched=false;
  }
  if(this.candidate!==target.direction){this.candidate=target.direction;this.dwell=0;}this.dwell+=dt;
  if(this.dwell<(this.policy.dwellMs||180))return;
  const next=this.policy.directions?.[target.direction];if(!next||!this.playback.config.animations[next])return;
  // Idle paws are grounded; a small reaction delay precedes the full recorded
  // gesture. Existing non-idle actions are never interrupted.
  this.playback.setState(next,true);this.previousState=next;this.triggerCount++;this.latched=true;this.lastTriggerPoint={...this.pointer};this.candidate=null;this.dwell=0;this.onTrigger({state:next,direction:target.direction});
 }
}
