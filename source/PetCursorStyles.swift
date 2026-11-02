import AppKit

final class PetCursorStyles {
 weak var owner:PetApp?
 static func image(_ name:String)->NSImage?{Bundle.main.url(forResource:"cursor-"+name,withExtension:"png").flatMap{NSImage(contentsOf:$0)}}
 static func cursor(_ name:String,_ hotspot:NSPoint)->NSCursor{
  guard let im=image(name) else{return .arrow};im.size=NSSize(width:40,height:40);return NSCursor(image:im,hotSpot:hotspot)
 }
 static let click=cursor("click",NSPoint(x:5,y:3))
 static let clickDown=cursor("click-down",NSPoint(x:5,y:3))
 static var arrow:NSCursor{CGEventSource.buttonState(.combinedSessionState,button:.left) ? clickDown:click}
 let pat=cursor("pat",NSPoint(x:6,y:25))
 let stroke=cursor("stroke",NSPoint(x:8,y:7))
 let grab=cursor("grab",NSPoint(x:18,y:17))
 var lastPoint:NSPoint?
 var lastTime:TimeInterval?
 var lastMoved=TimeInterval.zero
 var lastStyle=""
 var pushedDrag=false
 init(owner:PetApp){self.owner=owner}
 func beginDrag(){
  guard !pushedDrag else{return};pushedDrag=true;grab.push();owner?.pettingHandCursor=grab;grab.set()
 }
 func endDrag(){
  if pushedDrag{NSCursor.pop();pushedDrag=false};lastPoint=nil;lastTime=nil;lastStyle="";owner?.pettingHandCursor=pat
 }
 /// Apply the exact approved bitmap on the native transparent canvas too.
 @discardableResult func applyDefault(at point:NSPoint)->Bool{
  guard let o=owner,o.loaded,o.window.isVisible,!o.dragging,!o.basics.userHidden,!o.basics.systemSuspended,!o.basics.fullscreenHidden,o.window.frame.contains(point),o.basics.canReceivePointer(point),!o.isOnCat(point),!(o.teaserCursor.enabled && o.isNearCat(point)) else{return false}
  for panel in NSApp.windows where panel !== o.window && panel !== o.pettingCursorWindow && panel.isVisible && panel.frame.contains(point){return false}
  Self.arrow.set();return true
 }
 func update(){
  guard let o=owner else{return}
  if o.dragging{grab.set();return}
  guard !o.teaserCursor.enabled else{lastPoint=nil;lastTime=nil;lastStyle="";return}
  let point=NSEvent.mouseLocation,now=ProcessInfo.processInfo.systemUptime
  guard o.isOnCat(point),!o.basics.effectivePaused,o.basics.canReceivePointer(point) else{lastPoint=nil;lastTime=nil;lastMoved=0;lastStyle="";o.pettingHandCursor=pat;applyDefault(at:point);return}
  if let last=lastPoint,let time=lastTime,now-time<0.2,hypot(point.x-last.x,point.y-last.y)>0.8{lastMoved=now}
  lastPoint=point;lastTime=now
  let age=now-lastMoved
  if age<0.24{
   let opacity=max(0,1-age/0.24)
   let image=strokeImage(opacity:opacity)
   let cursor=NSCursor(image:image,hotSpot:NSPoint(x:12,y:11));o.pettingHandCursor=cursor
   if o.pettingCursorActive{cursor.set()};lastStyle="stroke"
  }else if lastStyle != "pat" || o.pettingHandCursor !== pat{
   o.pettingHandCursor=pat;if o.pettingCursorActive{pat.set()};lastStyle="pat"
  }
 }
 func strokeImage(opacity:Double)->NSImage{
  let result=NSImage(size:NSSize(width:48,height:48));result.lockFocus()
  let im=Self.image("stroke");im?.draw(in:NSRect(x:4,y:4,width:40,height:40))
  if opacity>0{
   NSColor(calibratedRed:0.45,green:0.57,blue:0.38,alpha:opacity*0.85).setStroke()
   for offset in [0.0,4.0]{
    let line=NSBezierPath();line.lineWidth=1.4;line.lineCapStyle = .round;line.move(to:NSPoint(x:3+offset,y:30+offset));line.curve(to:NSPoint(x:11+offset,y:40+offset),controlPoint1:NSPoint(x:3+offset,y:35+offset),controlPoint2:NSPoint(x:7+offset,y:39+offset));line.stroke()
   }
  }
  result.unlockFocus();return result
 }
 func smokeChecks()->[[String:Any]]{
  var checks:[[String:Any]]=[]
  for id in ["default","pat","stroke","grab","click","click-down"]{checks.append(["control":"approved \(id) cursor artwork is bundled","ok":Self.image(id) != nil])}
  let legacy=Bundle.main.url(forResource:"petting-hand",withExtension:"png")
  checks.append(["control":"legacy cursor removed from application resources","ok":legacy==nil])
  if let dir=owner?.smokeDir{
   for (name,image) in [("stroke-moving",strokeImage(opacity:1)),("stroke-stopped",strokeImage(opacity:0))]{if let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]){try? png.write(to:dir.appendingPathComponent(name+".png"))}}
  }
  return checks
 }
}

class PetClickButton:NSButton {
 override func resetCursorRects(){super.resetCursorRects();addCursorRect(bounds,cursor:PetCursorStyles.click)}
 override func mouseDown(with event:NSEvent){PetCursorStyles.clickDown.push();defer{NSCursor.pop()};super.mouseDown(with:event)}
}
final class PetMenuIcon:PetClickButton {}
final class PetMenuSurface:NSView {
 override func resetCursorRects(){super.resetCursorRects();addCursorRect(bounds,cursor:PetCursorStyles.arrow)}
}
