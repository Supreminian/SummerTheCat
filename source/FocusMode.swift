import AppKit

struct FocusTravelPlan {
 let origin:NSPoint
 let target:NSPoint
 let direction:String
 let oldRegion:NSRect
 let displacement:Double
}

enum FocusEvadePlanner {
 static func plan(window:NSRect,cat:NSRect,screen:NSRect,clearance:Double=24,margin:Double=12,fraction:Double=0.22)->FocusTravelPlan? {
  let left=max(0,window.minX-screen.minX-margin),right=max(0,screen.maxX-window.maxX-margin)
  guard max(left,right)>8 else{return nil}
  let required=cat.width+clearance,preferred=max(required,screen.width*fraction)
  let goRight=right>=left,available=goRight ? right:left
  let distance=min(available,preferred)
  return FocusTravelPlan(origin:window.origin,target:NSPoint(x:window.minX+(goRight ? distance:-distance),y:window.minY),direction:goRight ? "right":"left",oldRegion:cat,displacement:distance)
 }
 static func position(plan:FocusTravelPlan,frame:Double,start:Double,end:Double)->NSPoint {
  let raw=max(0,min(1,(frame-start)/max(1,end-start))),p=raw*raw*(3-2*raw)
  return NSPoint(x:plan.origin.x+(plan.target.x-plan.origin.x)*p,y:plan.origin.y)
 }
}
