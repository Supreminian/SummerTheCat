import AppKit

final class PetMenuRow:PetClickButton {
 var hovered=false
 override func updateTrackingAreas(){super.updateTrackingAreas();for area in trackingAreas{removeTrackingArea(area)};addTrackingArea(NSTrackingArea(rect:bounds,options:[.activeAlways,.mouseEnteredAndExited,.inVisibleRect],owner:self,userInfo:nil))}
 override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
 override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
 override func draw(_ dirtyRect:NSRect){
  if hovered || isHighlighted{NSColor(calibratedRed:0.90,green:0.94,blue:0.88,alpha:1).setFill();NSBezierPath(roundedRect:bounds,xRadius:10,yRadius:10).fill()}
  (title as NSString).draw(at:NSPoint(x:10,y:8),withAttributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor(calibratedRed:0.16,green:0.24,blue:0.20,alpha:1)])
 }
}

/// Separate small input surfaces keep the surrounding desktop clickable.
final class FloatingPetMenu {
 weak var owner:PetApp?
 let button:NSPanel
 let menu:NSPanel
 let icon=PetMenuIcon()
 var teaserRow:PetMenuRow?
 var suppressUntilLeave=false
 var opened=false
 var hoveredAt:Date?
 var leftAt:Date?
 var revision=0
 init(owner:PetApp){
  self.owner=owner
  func panel(_ size:NSSize)->NSPanel{
   let p=NSPanel(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
   p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
   p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
   return p
  }
  button=panel(NSSize(width:48,height:48));menu=panel(NSSize(width:180,height:252))
  icon.frame=NSRect(x:0,y:0,width:48,height:48);icon.isBordered=false;icon.imageScaling = .scaleProportionallyUpOrDown
  icon.image=asset("menu-default");icon.target=self;icon.action=#selector(toggle);icon.toolTip="夏天的菜单";icon.setAccessibilityLabel("打开夏天的菜单")
  button.contentView?.addSubview(icon)
  let surface=PetMenuSurface(frame:NSRect(x:0,y:0,width:180,height:252));surface.wantsLayer=true
  surface.layer?.backgroundColor=NSColor(calibratedRed:0.988,green:0.992,blue:0.976,alpha:0.98).cgColor
  surface.layer?.cornerRadius=18;surface.layer?.borderWidth=1;surface.layer?.borderColor=NSColor(calibratedRed:0.82,green:0.88,blue:0.82,alpha:1).cgColor
  let title=NSTextField(labelWithString:"夏天的小菜单");title.frame=NSRect(x:16,y:215,width:150,height:22);title.font = .systemFont(ofSize:12,weight:.semibold);title.textColor = .secondaryLabelColor;surface.addSubview(title)
  for (index,label) in ["和夏天聊聊", "AI 连接设置", "宠物详情", "暂停 / 继续", "逗猫棒：关闭", "更多功能…"].enumerated(){
   let row=PetMenuRow(title:label,target:self,action:#selector(selectItem(_:)));row.tag=index;row.frame=NSRect(x:10,y:179-index*34,width:160,height:32);row.bezelStyle = .inline;row.alignment = .left;row.font = .systemFont(ofSize:13);row.contentTintColor=NSColor(calibratedRed:0.25,green:0.40,blue:0.30,alpha:1);surface.addSubview(row);if index==4{teaserRow=row}
  }
  menu.contentView=surface;menu.hasShadow=true
 }
 func asset(_ name:String)->NSImage?{Bundle.main.url(forResource:name,withExtension:"png").flatMap{NSImage(contentsOf:$0)}}
 @objc func toggle(){suppressUntilLeave=opened;setOpen(!opened)}
 @objc func selectItem(_ sender:NSButton){
  guard let o=owner else{return};suppressUntilLeave=true;setOpen(false)
  switch sender.tag{
   case 0:o.showConversation(nil)
   case 1:o.showAISettings(nil)
   case 2:o.showDetails(nil)
   case 3:o.togglePause()
   case 4:o.toggleTeaser()
   default:
    let m=o.makeMenu();m.popUp(positioning:nil,at:NSPoint(x:0,y:48),in:icon)
  }
 }
 func setOpen(_ value:Bool){
  guard opened != value else{return};opened=value;revision+=1;let token=revision
  icon.image=asset(value ? "menu-hover":"menu-default")
  if value{menu.alphaValue=0;menu.orderFrontRegardless()}
  NSAnimationContext.runAnimationGroup({ctx in ctx.duration=value ? 0.4:0.22;ctx.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut);menu.animator().alphaValue=value ? 1:0},completionHandler:{[weak self] in guard let self=self,self.revision==token,!self.opened else{return};self.menu.orderOut(nil)})
 }
 func smokeChecks()->[[String:Any]]{
  update(pointer:NSPoint(x:-10000,y:-10000))
  let center=NSPoint(x:button.frame.midX,y:button.frame.midY)
  update(pointer:center)
  let waits = !opened
  hoveredAt=Date().addingTimeInterval(-0.3);update(pointer:center)
  let opens=opened && menu.isVisible
  update(pointer:NSPoint(x:menu.frame.midX,y:menu.frame.midY))
  let stays=opened
  leftAt=Date().addingTimeInterval(-0.4);update(pointer:NSPoint(x:-10000,y:-10000))
  let closes = !opened
  setOpen(true);menu.alphaValue=1
  if let dir=owner?.smokeDir,let view=menu.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);if let data=bitmap.representation(using:.png,properties:[:]){try? data.write(to:dir.appendingPathComponent("floating-menu.png"))}}
  setOpen(false)
  let screen=owner?.window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
  return [["control":"floating menu waits for hover then opens", "ok":waits && opens],
   ["control":"pointer can enter floating menu without closing it", "ok":stays],
   ["control":"floating menu closes after pointer leaves", "ok":closes],
   ["control":"approved default and hover images are bundled", "ok":asset("menu-default") != nil && asset("menu-hover") != nil],
   ["control":"floating menu stays within the visible screen", "ok":screen.contains(button.frame) && screen.contains(menu.frame)]]
 }
 func update(pointer:NSPoint?=nil){
  guard let o=owner else{return}
  let teaserTitle=o.teaserCursor.enabled ? "逗猫棒：开启":"逗猫棒：关闭"
  if teaserRow?.title != teaserTitle{teaserRow?.title=teaserTitle;teaserRow?.needsDisplay=true}
  guard o.loaded,o.window.isVisible,!o.basics.userHidden,!o.basics.systemSuspended,!o.basics.fullscreenHidden else{setOpen(false);button.orderOut(nil);menu.orderOut(nil);hoveredAt=nil;return}
  let cat=o.focusCatRect(),screen=o.window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
  let x=min(screen.maxX-54,max(screen.minX+4,cat.maxX+8)),y=min(screen.maxY-52,max(screen.minY+6,cat.midY-24))
  let frame=NSRect(x:x,y:y,width:48,height:48)
  if button.frame != frame{button.setFrame(frame,display:false)}
  let mf=NSRect(x:min(screen.maxX-186,max(screen.minX+6,x-126)),y:min(screen.maxY-258,max(screen.minY+6,y+54)),width:180,height:252)
  if menu.frame != mf{menu.setFrame(mf,display:false)}
  let level=NSWindow.Level(rawValue:o.window.level.rawValue+2);button.level=level;menu.level=level
  if !button.isVisible{button.orderFrontRegardless()}
  let point=pointer ?? NSEvent.mouseLocation
  let over=button.frame.contains(point) && !o.dragging && o.menuOpenedAt==nil
  // The narrow bridge between the button and panel keeps navigation continuous.
  let bridge=NSRect(x:frame.minX,y:frame.maxY,width:frame.width,height:max(0,mf.minY-frame.maxY))
  let inMenu=opened && (menu.frame.contains(point) || bridge.contains(point))
  if over || inMenu{
   leftAt=nil
   if hoveredAt==nil{hoveredAt=Date()}
   if !opened,!suppressUntilLeave,Date().timeIntervalSince(hoveredAt!)>=0.18{setOpen(true)}
  }else{
   hoveredAt=nil;suppressUntilLeave=false
   if leftAt==nil{leftAt=Date()}
   if opened,Date().timeIntervalSince(leftAt!)>=0.3,o.menuOpenedAt==nil{setOpen(false)}
  }
 }
}
