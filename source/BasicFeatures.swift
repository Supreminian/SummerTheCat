import AppKit
import Carbon
import ServiceManagement
import Darwin

enum DesktopInstance {
 static var descriptor:Int32 = -1
 static func acquire()->Bool {
  if let existing=NSRunningApplication.runningApplications(withBundleIdentifier:"local.summerthecat.v30.openai").first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}){existing.activate(options:[.activateIgnoringOtherApps]);DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("local.summerthecat.v30.openai.show"),object:nil,userInfo:nil,deliverImmediately:true);return false}
  let directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("SummerTheCat-v30-OpenAI",isDirectory:true)
  try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  descriptor=open(directory.appendingPathComponent("instance.lock").path,O_CREAT|O_RDWR,0o600)
  guard descriptor>=0,flock(descriptor,LOCK_EX|LOCK_NB)==0 else{
   DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("local.summerthecat.v30.openai.show"),object:nil,userInfo:nil,deliverImmediately:true)
   return false
  };return true
 }
}

final class DesktopControls:NSObject {
 weak var owner:PetApp?
 let defaults:UserDefaults
 var positionLocked=false,alwaysOnTop=true,userHidden=false,hideFullscreen=false
 var suspendedReasons=Set<String>();var fullscreenHidden=false;var fullscreenRevealRequested=false
 var systemSuspended:Bool {!suspendedReasons.isEmpty}
 var effectivePaused:Bool {systemSuspended || userHidden || fullscreenHidden || owner?.paused==true || owner?.menuOpenedAt != nil}
 var heartbeat:Timer?,hotkeyHandler:EventHandlerRef?,hotkeys:[EventHotKeyRef]=[];var keyMonitor:Any?;var heldKeys=Set<UInt32>()
 var shortcutProfile="controlOption",shortcutFailure=false
 var pointerCheck=Date.distantPast;var cachedPointerAvailable=true
 var recoveryCount=0;var recoveryStarted=Date();var lastHeartbeat=Date()
 init(owner:PetApp){self.owner=owner;defaults=owner.smoke ? UserDefaults(suiteName:"SummerTheCat-Smoke-\(ProcessInfo.processInfo.processIdentifier)")!:UserDefaults.standard;super.init()}
 func start(){
  positionLocked=defaults.bool(forKey:"positionLocked");alwaysOnTop=defaults.object(forKey:"alwaysOnTop")==nil || defaults.bool(forKey:"alwaysOnTop");userHidden=defaults.bool(forKey:"petHidden");hideFullscreen=defaults.bool(forKey:"hideFullscreen")
  shortcutProfile=defaults.string(forKey:"shortcutProfile") ?? "controlOption";applyLayers();registerShortcuts();applyVisibility()
  let ws=NSWorkspace.shared.notificationCenter
  ws.addObserver(self,selector:#selector(willSleep),name:NSWorkspace.willSleepNotification,object:nil)
  ws.addObserver(self,selector:#selector(didWake),name:NSWorkspace.didWakeNotification,object:nil)
  ws.addObserver(self,selector:#selector(displaySleep),name:NSWorkspace.screensDidSleepNotification,object:nil)
  ws.addObserver(self,selector:#selector(displayWake),name:NSWorkspace.screensDidWakeNotification,object:nil)
  NotificationCenter.default.addObserver(self,selector:#selector(screensChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
  let dc=DistributedNotificationCenter.default()
  dc.addObserver(self,selector:#selector(locked),name:NSNotification.Name("com.apple.screenIsLocked"),object:nil)
  dc.addObserver(self,selector:#selector(unlocked),name:NSNotification.Name("com.apple.screenIsUnlocked"),object:nil)
  dc.addObserver(self,selector:#selector(showFromAnotherInstance),name:NSNotification.Name("local.summerthecat.v30.openai.show"),object:nil)
  heartbeat=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self]_ in self?.checkFullscreen()}
  RunLoop.main.add(heartbeat!,forMode:.common)
 }
 func stop(){if owner?.smoke==true{defaults.removePersistentDomain(forName:"SummerTheCat-Smoke-\(ProcessInfo.processInfo.processIdentifier)")};heartbeat?.invalidate();unregisterShortcuts();NSWorkspace.shared.notificationCenter.removeObserver(self);NotificationCenter.default.removeObserver(self);DistributedNotificationCenter.default().removeObserver(self);defaults.synchronize()}
 func applyLayers(){guard let o=owner else{return};o.window.level=alwaysOnTop ? .floating:.normal;let layer=alwaysOnTop ? NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+1):NSWindow.Level.normal;o.pettingCursorWindow?.level=layer;o.focusMenuWindow?.level=layer}
 func canReceivePointer(_ point:NSPoint)->Bool {
  guard !alwaysOnTop,let o=owner else{return true}
  if Date().timeIntervalSince(pointerCheck)<0.1{return cachedPointerAvailable};pointerCheck=Date();cachedPointerAvailable=true
  let cgPoint=CGPoint(x:point.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-point.y)
  if let windows=CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow,.excludeDesktopElements],CGWindowID(o.window.windowNumber)) as? [[String:Any]]{
   for w in windows where w[kCGWindowOwnerPID as String] as? Int32 != ProcessInfo.processInfo.processIdentifier{
    if let b=w[kCGWindowBounds as String] as? NSDictionary,let rect=CGRect(dictionaryRepresentation:b),rect.contains(cgPoint){cachedPointerAvailable=false;break}
   }
  };return cachedPointerAvailable
 }
 func applyVisibility(){
  guard let o=owner else{return}
  if userHidden || fullscreenHidden || systemSuspended{o.restorePettingCursor();o.focusMenuWindow?.orderOut(nil);o.window.orderOut(nil)}else{o.window.orderFrontRegardless()}
  applyPause();o.refreshMenu()
 }
 func applyPause(){if !effectivePaused{lastHeartbeat=Date()};owner?.updateTickTimer(effectivePaused ? 0.25:1.0/60);owner?.web?.evaluateJavaScript("setPaused(\(effectivePaused))")}
 func setSuspended(_ reason:String,_ value:Bool){if value{suspendedReasons.insert(reason)}else{suspendedReasons.remove(reason)};owner?.cancelFocusTravel();owner?.lastTick=Date();applyVisibility()}
 @objc func willSleep(){setSuspended("sleep",true)}
 @objc func didWake(){setSuspended("sleep",false);owner?.constrain()}
 @objc func displaySleep(){setSuspended("display",true)}
 @objc func displayWake(){setSuspended("display",false)}
 @objc func locked(){setSuspended("lock",true)}
 @objc func unlocked(){setSuspended("lock",false)}
 @objc func screensChanged(){owner?.cancelFocusTravel();owner?.constrain();owner?.savePosition();checkFullscreen()}
 @objc func showFromAnotherInstance(){userHidden=false;defaults.set(false,forKey:"petHidden");applyVisibility()}
 @objc func toggleVisible(){userHidden.toggle();defaults.set(userHidden,forKey:"petHidden");owner?.cancelFocusTravel();applyVisibility()}
 @objc func toggleLocked(){positionLocked.toggle();defaults.set(positionLocked,forKey:"positionLocked");owner?.cancelFocusTravel();owner?.refreshMenu()}
 @objc func toggleTop(){alwaysOnTop.toggle();defaults.set(alwaysOnTop,forKey:"alwaysOnTop");applyLayers();owner?.refreshMenu()}
 @objc func toggleFullscreen(){hideFullscreen.toggle();defaults.set(hideFullscreen,forKey:"hideFullscreen");checkFullscreen();owner?.refreshMenu()}
 static func screenFor(_ frame:NSRect,_ screens:[NSRect])->NSRect? {
  screens.max{a,b in let x=a.intersection(frame),y=b.intersection(frame);return max(0,x.width)*max(0,x.height)<max(0,y.width)*max(0,y.height)}
 }
 static func constrained(_ frame:NSRect,to screen:NSRect)->NSRect {
  let size=NSSize(width:min(frame.width,screen.width),height:min(frame.height,screen.height))
  return NSRect(x:max(screen.minX,min(frame.minX,screen.maxX-size.width)),y:max(screen.minY,min(frame.minY,screen.maxY-size.height)),width:size.width,height:size.height)
 }
 @objc func moveToScreen(_ item:NSMenuItem){guard let index=item.representedObject as? Int,NSScreen.screens.indices.contains(index),let o=owner else{return};o.cancelFocusTravel();let screen=NSScreen.screens[index].visibleFrame;o.window.setFrameOrigin(NSPoint(x:screen.midX-o.window.frame.width/2,y:screen.minY));o.constrain();o.savePosition()}
 func checkFullscreen(){
  guard let o=owner,!o.smoke,o.menuOpenedAt==nil else{return};if o.loaded,recoveryCount>0,Date().timeIntervalSince(recoveryStarted)>30,Date().timeIntervalSince(lastHeartbeat)<2{recoveryCount=0};if o.loaded,!effectivePaused,Date().timeIntervalSince(lastHeartbeat)>12{lastHeartbeat=Date();o.recoverRenderer("动画进程暂时没有响应");return};var hidden=false
  let foreground=NSWorkspace.shared.frontmostApplication;let app=foreground?.processIdentifier==ProcessInfo.processInfo.processIdentifier ? o.cursorPreviousApp:foreground
  if hideFullscreen,let app=app,app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
   let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]]{
   for w in windows where w[kCGWindowOwnerPID as String] as? Int32==app.processIdentifier && w[kCGWindowLayer as String] as? Int==0 {
    guard let b=w[kCGWindowBounds as String] as? NSDictionary,let r=CGRect(dictionaryRepresentation:b) else{continue}
    if let screen=o.window.screen,let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber{hidden=DesktopControls.coversScreen(r,CGDisplayBounds(number.uint32Value))};if hidden{break}
   }
  }
  if !hidden{fullscreenRevealRequested=false};if fullscreenRevealRequested{hidden=false}
  if hidden != fullscreenHidden{fullscreenHidden=hidden;o.cancelFocusTravel();applyVisibility()}
 }
 static func coversScreen(_ window:CGRect,_ screen:CGRect)->Bool {abs(window.minX-screen.minX)<3 && abs(window.minY-screen.minY)<3 && abs(window.width-screen.width)<3 && abs(window.height-screen.height)<3}
 @objc func chooseShortcuts(_ item:NSMenuItem){guard let profile=item.representedObject as? String else{return};shortcutProfile=profile;defaults.set(profile,forKey:"shortcutProfile");registerShortcuts();owner?.refreshMenu()}
 func unregisterShortcuts(){if let monitor=keyMonitor{NSEvent.removeMonitor(monitor)};keyMonitor=nil;heldKeys.removeAll();for key in hotkeys{UnregisterEventHotKey(key)};hotkeys=[];if let handler=hotkeyHandler{RemoveEventHandler(handler)};hotkeyHandler=nil}
 func registerShortcuts(){
  unregisterShortcuts();shortcutFailure=false;guard shortcutProfile != "off",owner?.smoke != true else{return}
  var types=[EventTypeSpec(eventClass:UInt32(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),EventTypeSpec(eventClass:UInt32(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
  let opaque=Unmanaged.passUnretained(self).toOpaque()
  let result=InstallEventHandler(GetApplicationEventTarget(),{_,event,data in
   guard let event=event,let data=data else{return OSStatus(eventNotHandledErr)}
   var id=EventHotKeyID();let status=GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
   guard status==noErr else{return status};let controls=Unmanaged<DesktopControls>.fromOpaque(data).takeUnretainedValue()
   if GetEventKind(event)==UInt32(kEventHotKeyReleased){controls.heldKeys.remove(id.id)}else{controls.performShortcut(id.id)};return noErr
  },2,&types,opaque,&hotkeyHandler)
  guard result==noErr else{shortcutFailure=true;return}
  let modifiers=UInt32(shortcutProfile=="commandOption" ? cmdKey|optionKey:controlKey|optionKey)
  for (id,key) in [(1,4),(2,35),(3,46)]{var ref:EventHotKeyRef?;let status=RegisterEventHotKey(UInt32(key),modifiers,EventHotKeyID(signature:0x53554D52,id:UInt32(id)),GetApplicationEventTarget(),0,&ref);if status==noErr,let ref=ref{hotkeys.append(ref)}else{shortcutFailure=true}}
  if shortcutFailure{unregisterShortcuts();return}
  keyMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp]){[weak self] event in
   guard let self=self,let id=[UInt16(4):UInt32(1),UInt16(35):UInt32(2),UInt16(46):UInt32(3)][event.keyCode] else{return event}
   if event.type == .keyUp,self.heldKeys.contains(id){self.heldKeys.remove(id);return nil}
   let required:NSEvent.ModifierFlags=self.shortcutProfile=="commandOption" ? [.command,.option]:[.control,.option]
   guard event.modifierFlags.intersection([.command,.control,.option,.shift])==required else{return event}
   if event.type == .keyDown,!event.isARepeat{self.performShortcut(id)};return nil
  }
 }
 func performShortcut(_ id:UInt32){
  guard !heldKeys.contains(id) else{return};heldKeys.insert(id)
  switch id{case 1:toggleVisible();case 2:owner?.togglePause();case 3:if let o=owner{o.setFocusMode(!o.focusModeEnabled)};default:break}
 }
 @objc func toggleLogin(){
  guard owner?.smoke != true else{return}
  do{if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval{try SMAppService.mainApp.unregister()}else{try SMAppService.mainApp.register()};owner?.refreshMenu()}catch{let alert=NSAlert();alert.messageText="无法更改开机启动";alert.informativeText=error.localizedDescription;alert.runModal()}
 }
 @objc func openLoginSettings(){SMAppService.openSystemSettingsLoginItems()}
 func settingsMenu()->NSMenu {
  let menu=NSMenu();menu.autoenablesItems=false
  func add(_ title:String,_ action:Selector,_ checked:Bool=false){let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;item.state=checked ? .on:.off;menu.addItem(item)}
  add(userHidden ? "显示猫咪":"隐藏猫咪",#selector(toggleVisible));add("锁定位置",#selector(toggleLocked),positionLocked);add("保持置顶",#selector(toggleTop),alwaysOnTop);add("全屏应用中隐藏",#selector(toggleFullscreen),hideFullscreen)
  let displays=NSMenu();for (i,screen) in NSScreen.screens.enumerated(){let item=NSMenuItem(title:screen.localizedName,action:#selector(moveToScreen(_:)),keyEquivalent:"");item.target=self;item.representedObject=i;displays.addItem(item)};let displayItem=NSMenuItem(title:"移动到显示器",action:nil,keyEquivalent:"");displayItem.submenu=displays;menu.addItem(displayItem)
  menu.addItem(.separator());add("开机启动",#selector(toggleLogin),SMAppService.mainApp.status == .enabled);if SMAppService.mainApp.status == .requiresApproval{add("允许开机启动…",#selector(openLoginSettings))}
  let shortcuts=NSMenu();for (title,profile) in [("⌃⌥ H 隐藏／显示 · P 暂停 · M 切换模式","controlOption"),("⌘⌥ H 隐藏／显示 · P 暂停 · M 切换模式","commandOption"),("关闭快捷键","off")]{let item=NSMenuItem(title:title,action:#selector(chooseShortcuts(_:)),keyEquivalent:"");item.target=self;item.representedObject=profile;item.state=profile==shortcutProfile ? .on:.off;shortcuts.addItem(item)};let keys=NSMenuItem(title:shortcutFailure ? "快捷键（组合已被占用，请更换）":"快捷键",action:nil,keyEquivalent:"");keys.submenu=shortcuts;menu.addItem(keys)
  menu.addItem(.separator());add("恢复默认设置",#selector(resetSettings));return menu
 }
 @objc func resetSettings(){
  let keys=["positionLocked","alwaysOnTop","petHidden","hideFullscreen","shortcutProfile","petScale","petX","petY","focusModeEnabled","mouseInteractionEnabled","randomBehaviorEnabled","tailMode","clickThrough","paused"]
  for key in keys{defaults.removeObject(forKey:key)}
  positionLocked=false;alwaysOnTop=true;userHidden=false;hideFullscreen=false;fullscreenHidden=false;shortcutProfile="controlOption"
  if owner?.smoke != true,SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval{try? SMAppService.mainApp.unregister()}
  if let o=owner{o.cancelFocusTravel();o.paused=false;o.clickThrough=false;o.resize(to:1);o.resetPosition();o.setFocusMode(false,persist:!o.smoke);o.setTailMode("random",persist:!o.smoke);o.savePosition()};applyLayers();registerShortcuts();applyVisibility()
 }
}

final class StatusSummonHoverView:NSView {
 weak var owner:PetApp?
 var area:NSTrackingArea?,hoverTimer:Timer?
 static let delay=0.45
 override func hitTest(_ point:NSPoint)->NSView? {nil}
 override func updateTrackingAreas(){
  if let area=area{removeTrackingArea(area)}
  let tracking=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
  addTrackingArea(tracking);area=tracking;super.updateTrackingAreas()
 }
 override func mouseEntered(with event:NSEvent){arm()}
 override func mouseExited(with event:NSEvent){cancel()}
 func arm(){
  cancel();let timer=Timer(timeInterval:Self.delay,repeats:false){[weak self]_ in
   guard let self=self,let owner=self.owner,owner.menuOpenedAt==nil,let window=self.window else{return}
   let rect=window.convertToScreen(self.convert(self.bounds,to:nil))
   guard rect.contains(NSEvent.mouseLocation) else{return};owner.summonFromMenuBar()
  };hoverTimer=timer;RunLoop.main.add(timer,forMode:.common)
 }
 func cancel(){hoverTimer?.invalidate();hoverTimer=nil}
 deinit{hoverTimer?.invalidate()}
}
