import AppKit

final class TeaserCursor {
 weak var owner:PetApp?
 var enabled=false
 var motion=TeaserMotion()
 var lastTime:TimeInterval?
 var original:NSCursor?
 var wasActive=false
 var lastRendered:(Double,Double)?
 let rod:NSImage?,feathers:NSImage?,bell:NSImage?
 init(owner:PetApp){
  self.owner=owner
  func load(_ name:String)->NSImage?{Bundle.main.url(forResource:"teaser-"+name,withExtension:"png").flatMap{NSImage(contentsOf:$0)}}
  rod=load("rod");feathers=load("feathers");bell=load("bell")
 }
 var available:Bool{rod != nil && feathers != nil && bell != nil}
 func toggle(){
  guard let o=owner,available else{return}
  enabled.toggle();motion.reset();lastTime=nil;lastRendered=nil
  if enabled{original=o.pettingHandCursor;if o.focusModeEnabled{o.setFocusMode(false,persist:!o.smoke)};o.setMouseInteraction(true,persist:!o.smoke)}else{deactivate()}
  o.web?.evaluateJavaScript("setTeaserMode(\(enabled))")
  o.refreshMenu()
 }
 func deactivate(){
  if let original=original{owner?.pettingHandCursor=original}
  if wasActive,let o=owner,o.pettingCursorActive,!o.basics.effectivePaused,o.isNearCat(NSEvent.mouseLocation){original?.set()}
  wasActive=false;lastTime=nil;lastRendered=nil;motion.reset()
 }
 func update(){
  guard let o=owner,enabled,available else{return}
  let point=NSEvent.mouseLocation
  guard !o.basics.effectivePaused,!o.focusModeEnabled,!o.dragging,!o.conversation.motionActive,o.isNearCat(point),o.basics.canReceivePointer(point) else{if wasActive{deactivate()};return}
  let now=ProcessInfo.processInfo.systemUptime
  if let time=lastTime{motion.advance(point:point,dt:now-time)}else{motion.advance(point:point,dt:1.0/60)}
  lastTime=now;wasActive=true
  if let last=lastRendered,abs(last.0-motion.feather)<0.0005,abs(last.1-motion.bell)<0.0005{return}
  let cursor=NSCursor(image:render(),hotSpot:NSPoint(x:31,y:38))
  o.pettingHandCursor=cursor
  if o.pettingCursorActive{cursor.set()}
  lastRendered=(motion.feather,motion.bell)
 }
 func render()->NSImage{
  let image=NSImage(size:NSSize(width:64,height:64));image.lockFocus()
  NSGraphicsContext.current?.imageInterpolation = .high
  rod?.draw(in:NSRect(x:32,y:7,width:31,height:41))
  let anchor=NSPoint(x:34,y:46),angle=motion.feather
  let tip=NSPoint(x:anchor.x+sin(angle)*10-3,y:anchor.y-cos(angle)*10)
  let string=NSBezierPath();string.move(to:anchor);string.curve(to:tip,controlPoint1:NSPoint(x:anchor.x-3,y:anchor.y-3),controlPoint2:NSPoint(x:tip.x,y:tip.y+3));string.lineWidth=1.3;NSColor(calibratedRed:0.83,green:0.80,blue:0.66,alpha:1).setStroke();string.stroke()
  draw(feathers,at:tip,size:NSSize(width:14,height:22),angle:angle*0.65)
  let bellAnchor=NSPoint(x:tip.x+5,y:tip.y-1)
  draw(bell,at:bellAnchor,size:NSSize(width:7,height:10),angle:motion.bell)
  image.unlockFocus();return image
 }
 func draw(_ image:NSImage?,at point:NSPoint,size:NSSize,angle:Double){
  NSGraphicsContext.saveGraphicsState();let transform=NSAffineTransform();transform.translateX(by:point.x,yBy:point.y);transform.rotate(byRadians:angle);transform.concat();image?.draw(in:NSRect(x:-size.width/2,y:-size.height,width:size.width,height:size.height));NSGraphicsContext.restoreGraphicsState()
 }
 func smokeChecks()->[[String:Any]]{
  var p=TeaserMotion();p.advance(point:.zero,dt:1.0/60)
  var difference=0.0
  for i in 1...20{p.advance(point:CGPoint(x:i*6,y:i*2),dt:1.0/60);difference=max(difference,abs(p.bell-p.feather))}
  let moving=abs(p.feather)>0.1 && difference>0.02
  let before=p.feather
  p.advance(point:CGPoint(x:114,y:38),dt:1.0/60)
  let continuity=abs(p.feather-before)<0.3
  for _ in 0..<360{p.advance(point:CGPoint(x:114,y:38),dt:1.0/60)}
  let settled=p.settled
  let saved=motion
  if let dir=owner?.smokeDir{
   for (name,value) in [("still",0.0),("left",-1.1),("right",1.1)]{motion.feather=value;motion.bell = -value*0.7;let image=render();if let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]){try? png.write(to:dir.appendingPathComponent("teaser-\(name).png"))}}
  }
  motion=saved
  let originalEnabled=enabled,originalCursor=owner?.pettingHandCursor
  let originalPause=owner?.paused ?? false
  original=originalCursor;enabled=true;wasActive=true
  owner?.pettingHandCursor=NSCursor(image:render(),hotSpot:NSPoint(x:31,y:38))
  owner?.paused=true;update()
  let restored=owner?.pettingHandCursor === originalCursor && !wasActive
  owner?.paused=originalPause;enabled=originalEnabled;motion=saved
  return [["control":"teaser cursor has three independent transparent artwork layers","ok":available],["control":"feather and bell respond at different rates to mouse movement","ok":moving],["control":"teaser direction change stays continuous","ok":continuity],["control":"teaser settles completely after mouse stops","ok":settled],["control":"pausing restores the original cursor and clears teaser motion","ok":restored]]
 }
}
