import AppKit
@main struct CheckFocus {
 static func main(){
  let screen=NSRect(x:0,y:0,width:1440,height:900)
  func check(_ x:Double,_ expected:String,_ screen:NSRect){
   let window=NSRect(x:x,y:screen.minY,width:512,height:320),cat=NSRect(x:x+196,y:screen.minY+34,width:150,height:174)
   let p=FocusEvadePlanner.plan(window:window,cat:cat,screen:screen)!
   precondition(p.direction==expected);precondition(p.target.x>=screen.minX+12 && p.target.x+512<=screen.maxX-12)
   let moved=cat.offsetBy(dx:p.target.x-p.origin.x,dy:0);precondition(!moved.intersects(cat))
   var last=p.origin.x
   for i in 0...100{let v=FocusEvadePlanner.position(plan:p,frame:Double(i)/100,start:0,end:1);precondition(v.y==p.origin.y);precondition(expected=="left" ? v.x<=last:v.x>=last);last=v.x}
   precondition(abs(last-p.target.x)<0.001)
  }
  check(40,"right",screen);check(870,"left",screen);check(-1400,"right",NSRect(x:-1440,y:100,width:1440,height:900))
  precondition(FocusEvadePlanner.plan(window:NSRect(x:0,y:0,width:512,height:320),cat:NSRect(x:196,y:34,width:150,height:174),screen:NSRect(x:0,y:0,width:512,height:900))==nil)
  print("Focus planner: both directions, full clearance, monotonic travel, screen bounds, secondary display and no-space case passed")
 }
}
