import Foundation

/// Two damped pendulums driven by cursor velocity; no idle random motion.
struct TeaserMotion {
 var feather=0.0,featherSpeed=0.0,bell=0.0,bellSpeed=0.0
 var previous:CGPoint?
 mutating func reset(){self=TeaserMotion()}
 mutating func advance(point:CGPoint,dt:Double){
  guard point.x.isFinite,point.y.isFinite,dt.isFinite,dt>0 else{return}
  guard let last=previous else{previous=point;return}
  previous=point
  guard dt<0.2,hypot(point.x-last.x,point.y-last.y)<500 else{featherSpeed=0;bellSpeed=0;return}
  let step=min(0.05,dt),vx=(point.x-last.x)/dt,vy=(point.y-last.y)/dt
  let target=max(-0.85,min(0.85,-vx*0.0009-vy*0.00025))
  let count=max(1,Int(ceil(step/0.008))),h=step/Double(count)
  for _ in 0..<count{
   featherSpeed += (105*(target-feather)-9*featherSpeed)*h
   feather += featherSpeed*h
   bellSpeed += (210*(target*1.15-bell)-8*bellSpeed)*h
   bell += bellSpeed*h
   feather=max(-1.1,min(1.1,feather));bell=max(-1.3,min(1.3,bell))
  }
  if abs(feather)<0.0003,abs(featherSpeed)<0.001{feather=0;featherSpeed=0}
  if abs(bell)<0.0003,abs(bellSpeed)<0.001{bell=0;bellSpeed=0}
 }
 var settled:Bool{feather==0 && bell==0 && featherSpeed==0 && bellSpeed==0}
}
