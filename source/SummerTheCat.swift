import AppKit
import WebKit
import ImageIO

struct Atlas: Codable {let file:String;let width:Int;let height:Int;let frameWidth:Int;let frameHeight:Int;let columns:Int;let rows:Int}
struct Motion: Codable {let file:String;let width:Int;let height:Int;let cellSize:Int;let columns:Int;let scale:Int;let encoding:String}
struct EvadeMotion:Codable {let startFrame:Double;let endFrame:Double}
struct FocusSettings:Codable {let triggerRect:[Double];let dwellMs:Double;let cooldownMs:Double;let minimumClearance:Double;let preferredTravelFraction:Double;let screenMargin:Double}
struct Animation: Codable {let evadeMotion:EvadeMotion?;let label:String;let row:Int;let frames:Int;let fps:Double;let loop:Bool;let speed:Double;let motion:Motion?;let restState:String?;let clip:Atlas?}
struct DisplayFrame:Codable {let width:Double;let height:Double;let paddingTop:Double}
struct MousePolicy: Codable {let anchor:[Double];let reach:[Double]}
struct PetConfig: Codable {let focusMode:FocusSettings?;let displayFrame:DisplayFrame?;let mouseInteraction:MousePolicy?;let schemaVersion:Int;let id:String;let name:String;let atlas:Atlas;let animations:[String:Animation];let defaultState:String?;let description:String?;let main:String?}
let actionIDs=["natural_sit","look","yawn","groom","ears"]
let pawIDs=["paw_up","paw_up_right","paw_right","paw_down_right","paw_down","paw_down_left","paw_left","paw_up_left"]
let stateIDs=actionIDs+["natural_sit_still"]+pawIDs+["evade_left","evade_right","thinking_enter","thinking_loop","thinking_exit"]

final class PetWindow:NSPanel {
 override var canBecomeKey:Bool {false}
 override var canBecomeMain:Bool {false}
}
// This transparent view owns a real macOS cursor; no second hand is painted.
final class PettingCursorView:NSView {
 weak var owner:PetApp?;var tracking:[NSTrackingArea]=[]
 override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
 override func resetCursorRects(){super.resetCursorRects();if let o=owner{addCursorRect(bounds,cursor:(o.teaserCursor.enabled || o.isOnCat(NSEvent.mouseLocation) ? o.pettingHandCursor:PetCursorStyles.arrow) ?? PetCursorStyles.arrow)}}
 override func updateTrackingAreas(){
  for area in tracking{removeTrackingArea(area)}
  tracking=[NSTrackingArea(rect:bounds,options:[.activeAlways,.mouseEnteredAndExited,.inVisibleRect],owner:self,userInfo:nil),NSTrackingArea(rect:bounds,options:[.activeInActiveApp,.cursorUpdate,.mouseMoved,.inVisibleRect],owner:self,userInfo:nil)]
  for area in tracking{addTrackingArea(area)};super.updateTrackingAreas()
 }
 override func mouseEntered(with event:NSEvent){if let o=owner{(o.teaserCursor.enabled || o.isOnCat(NSEvent.mouseLocation) ? o.pettingHandCursor:PetCursorStyles.arrow)?.set()}}
 override func mouseMoved(with event:NSEvent){if let o=owner{(o.teaserCursor.enabled || o.isOnCat(NSEvent.mouseLocation) ? o.pettingHandCursor:PetCursorStyles.arrow)?.set()}}
 override func cursorUpdate(with event:NSEvent){if let o=owner{(o.teaserCursor.enabled || o.isOnCat(NSEvent.mouseLocation) ? o.pettingHandCursor:PetCursorStyles.arrow)?.set()}}
 override func mouseDown(with event:NSEvent){
  guard let owner=owner,owner.window.frame.contains(NSEvent.mouseLocation) else{return};if event.clickCount>=2{owner.showConversation(nil);return};if owner.basics.positionLocked{owner.pet();return}
  let before=owner.window.frame.origin;owner.dragging=true;owner.cancelFocusTravel();owner.clearCursorInteraction();owner.cursorStyles.beginDrag();let down=NSEvent.mouseEvent(with:.leftMouseDown,location:owner.window.convertPoint(fromScreen:NSEvent.mouseLocation),modifierFlags:event.modifierFlags,timestamp:event.timestamp,windowNumber:owner.window.windowNumber,context:nil,eventNumber:event.eventNumber,clickCount:event.clickCount,pressure:event.pressure)
  if let down=down{owner.window.performDrag(with:down)};owner.dragging=false;owner.cursorStyles.endDrag();owner.constrain();owner.savePosition()
  if hypot(owner.window.frame.minX-before.x,owner.window.frame.minY-before.y)<3{owner.pet()}
 }
 override func rightMouseDown(with event:NSEvent){if let owner=owner{owner.showContextMenu(event,from:self)}}
}
// Only the visible cat region accepts input in focus mode; surrounding work space stays clear.
final class FocusMenuView:NSView {
 weak var owner:PetApp?
 override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
 override func rightMouseDown(with event:NSEvent){guard let owner=owner else{return};owner.showContextMenu(event,from:self)}
 override func mouseDown(with event:NSEvent){guard let owner=owner else{return};owner.tickFocusMode(NSEvent.mouseLocation,dt:200)}
}
final class PetView:WKWebView {
 weak var owner:PetApp?
 override func resetCursorRects(){super.resetCursorRects();addCursorRect(bounds,cursor:PetCursorStyles.arrow)}
 override func mouseDown(with event:NSEvent){
  guard let window=window else{return};if event.clickCount>=2{owner?.showConversation(nil);return};if owner?.basics.positionLocked==true{owner?.pet();return};let before=window.frame.origin;owner?.dragging=true;owner?.cancelFocusTravel();owner?.clearCursorInteraction();owner?.cursorStyles.beginDrag()
  window.performDrag(with:event);owner?.dragging=false;owner?.cursorStyles.endDrag()
  owner?.constrain();owner?.savePosition();if hypot(window.frame.origin.x-before.x,window.frame.origin.y-before.y)<3{owner?.pet()}
 }
 override func rightMouseDown(with event:NSEvent){if let owner=owner{owner.showContextMenu(event,from:self)}}
 override func scrollWheel(with event:NSEvent){}
}

final class PetApp:NSObject,NSApplicationDelegate,WKScriptMessageHandler,WKNavigationDelegate,NSMenuDelegate {
 var bodyMask:Data?;var bodyMaskX=0;var bodyMaskY=0;var bodyMaskSize=0
 var bodyHit=false;var bodyHitPoint=NSPoint.zero;var hitProbeInFlight=false;var lastHitProbe=Date.distantPast
 var pettingCursorWindow:NSPanel?;var pettingHandCursor:NSCursor?;var pettingCursorActive=false;var cursorPreviousApp:NSRunningApplication?;var cursorEventMonitor:Any?
 var window:PetWindow!;var web:PetView!;var status:NSStatusItem!;var config:PetConfig!;var packURL:URL!
 var detailsWindow:NSWindow?;var detailsWeb:WKWebView?;var detailsSmokeStarted=false
 lazy var cursorStyles=PetCursorStyles(owner:self)
 lazy var teaserCursor=TeaserCursor(owner:self)
 lazy var floatingMenu=FloatingPetMenu(owner:self)
 lazy var conversation=ConversationUI(owner:self)
 lazy var basics=DesktopControls(owner:self);var statusSummonView:StatusSummonHoverView?;var activeContextMenu:NSMenu?;var contextMenuMonitor:Any?;var contextMenuShowing=false;var menuRefreshQueued=false;var menuOpenedAt:Date?;var pendingState:String?;var tailMode="random";var randomBehaviorEnabled=true;var mouseInteractionEnabled=true;var cursorSendInFlight=false;var lastCursorSent=Date.distantPast
 var focusMenuWindow:PetWindow?;var focusModeEnabled=false;var focusRun:FocusTravelPlan?;var focusRunState:String?;var focusReady=false;var focusHoverMs=0.0;var focusCooldownUntil=Date.distantPast
 var state="natural_sit",automatic=false,paused=false,clickThrough=false,dragging=false,direction=1
 var smokeChecks:[String:Any]=[:]
 var smokeFinished=false
 var tickInterval=1.0/60;var timer:Timer?;var deadline=Date().addingTimeInterval(6);var lastTick=Date();var loaded=false
 let smoke=CommandLine.arguments.contains("--smoke-test")
 var smokeDir:URL? {if let i=CommandLine.arguments.firstIndex(of:"--smoke-test"),CommandLine.arguments.count>i+1{return URL(fileURLWithPath:CommandLine.arguments[i+1],isDirectory:true)};return nil}
 func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{basics.showFromAnotherInstance();return true}
 func applicationDidFinishLaunching(_ notification:Notification){
  if let dir=smokeDir{try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)}
  NSApp.setActivationPolicy(.accessory);StandardEditing.install()
  guard let resource=Bundle.main.resourceURL else{return}
  do{try readPack(resource.appendingPathComponent("pet-pack"))}catch{fail(error.localizedDescription);return}
  window=PetWindow(contentRect:NSRect(x:0,y:0,width:256,height:256),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=false;window.level = .floating
  window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];window.hidesOnDeactivate=false;window.isReleasedWhenClosed=false
  let wc=WKWebViewConfiguration();wc.userContentController.add(self,name:"pet")
  web=PetView(frame:window.contentView!.bounds,configuration:wc);web.owner=self;web.navigationDelegate=self
  web.setValue(false,forKey:"drawsBackground");web.autoresizingMask=[.width,.height];window.contentView=web
  status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
  status.isVisible=true
  if let button=status.button {
   let paw=NSImage(systemSymbolName:"pawprint.fill",accessibilityDescription:"猫爪")
   paw?.size=NSSize(width:16,height:16);paw?.isTemplate=true
   button.image=paw;button.title="夏天 AI";button.imagePosition = .imageLeading
  }
  status.menu=makeMenu();setupStatusSummon()
  let defaults=UserDefaults.standard;if let mode=defaults.string(forKey:"tailMode"),["random","moving","still"].contains(mode){tailMode=mode};let scale=defaults.double(forKey:"petScale");resize(to:scale>0 ? scale:1)
  if defaults.object(forKey:"petX") != nil {window.setFrameOrigin(NSPoint(x:defaults.double(forKey:"petX"),y:defaults.double(forKey:"petY")))}else{resetPosition()}
  constrain();window.orderFrontRegardless()
  do{web.loadHTMLString(try String(contentsOf:resource.appendingPathComponent("pet.html"),encoding:.utf8),baseURL:nil)}catch{fail(error.localizedDescription)}
  setupPettingCursor();setupFocusMenu();basics.start()
  contextMenuMonitor=NSEvent.addLocalMonitorForEvents(matching:[.rightMouseDown,.leftMouseDown]){[weak self] event in
   guard let self=self,event.type == .rightMouseDown || event.modifierFlags.contains(.control),let target=event.window,
    target===self.window || target===self.pettingCursorWindow || target===self.focusMenuWindow,let view=target.contentView else{return event}
   self.showContextMenu(event,from:view);return nil
  }
  cursorEventMonitor=NSEvent.addLocalMonitorForEvents(matching:[.cursorUpdate,.mouseMoved,.mouseEntered]){[weak self] event in
   guard let self=self,self.pettingCursorActive,(self.teaserCursor.enabled ? self.isNearCat(NSEvent.mouseLocation):self.isOnCat(NSEvent.mouseLocation)) else{return event}
   self.pettingHandCursor?.set();return event.type == .cursorUpdate ? nil:event
  }
  updateTickTimer(basics.effectivePaused ? 0.25:1.0/60)
  NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(woke),name:NSWorkspace.didWakeNotification,object:nil)
  if smoke{DispatchQueue.main.asyncAfter(deadline:.now()+15){if !self.loaded{self.finishSmoke(error:"WKWebView failed to load within 15 seconds")}};DispatchQueue.main.asyncAfter(deadline:.now()+60){if !self.smokeFinished{self.finishSmoke(error:"Native UI checks timed out; unlock macOS and keep the display active before testing")}}}
 }
 func readPack(_ url:URL)throws{
  let data=try Data(contentsOf:url.appendingPathComponent("pet.json"));guard data.count<1_000_000 else{throw NSError(domain:"PetPack",code:0,userInfo:[NSLocalizedDescriptionKey:"配置文件过大"])};let candidate=try JSONDecoder().decode(PetConfig.self,from:data)
  let a=candidate.atlas
  guard candidate.schemaVersion==1,a.file=="spritsheet.webp",a.width>0,a.height>0,a.width<=16383,a.height<=16383,a.frameWidth>0,a.frameWidth<=1024,a.frameHeight>0,a.frameHeight<=1024,a.columns>0,a.columns<=60,a.rows>0,a.rows<=32,a.width==a.frameWidth*a.columns,a.height==a.frameHeight*a.rows,Int64(a.width)*Int64(a.height)<=32_000_000 else{throw NSError(domain:"PetPack",code:1,userInfo:[NSLocalizedDescriptionKey:"宠物包的精灵图配置无效"])}
  guard candidate.animations.count>=1,candidate.animations.count<=stateIDs.count,candidate.animations["natural_sit"]?.clip != nil,candidate.defaultState=="natural_sit" else{throw NSError(domain:"PetPack",code:2,userInfo:[NSLocalizedDescriptionKey:"此版本支持自然静坐、静坐尾巴控制、左右张望、打哈欠、舔毛和动耳朵视频动作"])}
  for (id,s) in candidate.animations {guard stateIDs.contains(id),s.row>=0,s.row<a.rows,(s.frames==30 || s.clip != nil),s.fps>0,s.fps<=60,s.speed.isFinite,s.speed>=0,s.speed<=300,s.restState==nil || candidate.animations[s.restState!] != nil else{throw NSError(domain:"PetPack",code:2,userInfo:[NSLocalizedDescriptionKey:"动作配置无效：\(id)"])};if let m=s.motion {guard stateIDs.contains(id),m.file=="motion/\(id).flow",m.width==1920,m.height==64,m.cellSize==64,m.columns==30,m.scale==32,m.encoding=="int16-le-forward-xy-backward-xy" else{throw NSError(domain:"PetPack",code:5,userInfo:[NSLocalizedDescriptionKey:"动作过渡数据配置无效：\(id)"])}}}
  for (id,s) in candidate.animations {if let clip=s.clip {
   guard clip.file=="clips/\(id).webp",[256,512,768].contains(clip.frameWidth),(clip.frameHeight==clip.frameWidth || ([512,768].contains(clip.frameWidth) && clip.frameHeight==640)),clip.columns>0,clip.columns<=32,clip.rows>0,clip.rows<=32,clip.width==clip.columns*clip.frameWidth,clip.height==clip.rows*clip.frameHeight,s.frames>=30,s.frames<=600,s.frames<=clip.columns*clip.rows,s.motion==nil else{throw NSError(domain:"PetPack",code:7,userInfo:[NSLocalizedDescriptionKey:"完整视频帧配置无效：\(id)"])}
   let bytes=try Data(contentsOf:url.appendingPathComponent(clip.file));guard bytes.count<30_000_000,let src=CGImageSourceCreateWithData(bytes as CFData,nil),CGImageSourceGetCount(src)==1,let props=CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [CFString:Any],props[kCGImagePropertyPixelWidth] as? Int==clip.width,props[kCGImagePropertyPixelHeight] as? Int==clip.height else{throw NSError(domain:"PetPack",code:8,userInfo:[NSLocalizedDescriptionKey:"完整视频帧图集损坏：\(id)"])}
  }}
  let image=try Data(contentsOf:url.appendingPathComponent(a.file));guard image.count<30_000_000 else{throw NSError(domain:"PetPack",code:3,userInfo:[NSLocalizedDescriptionKey:"精灵图超过 30 MB"])}
  guard let src=CGImageSourceCreateWithData(image as CFData,nil),CGImageSourceGetCount(src)==1,let props=CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [CFString:Any],props[kCGImagePropertyPixelWidth] as? Int==a.width,props[kCGImagePropertyPixelHeight] as? Int==a.height else{throw NSError(domain:"PetPack",code:4,userInfo:[NSLocalizedDescriptionKey:"精灵图损坏、尺寸不匹配，或不是静态图集"])}
  config=candidate;packURL=url
 }
 func webViewWebContentProcessDidTerminate(_ webView:WKWebView){if webView===web{recoverRenderer("动画进程已退出")}else if webView===detailsWeb{sendDetailsProfile()}}
 func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){if webView===detailsWeb{sendDetailsProfile()}else if basics.recoveryCount<=2{sendPack()}}
 func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy)->Void){decisionHandler(webView===detailsWeb && navigationAction.navigationType == .linkActivated ? .cancel:.allow)}
 func sendPack(){do{
  let c=try JSONSerialization.jsonObject(with:Data(contentsOf:packURL.appendingPathComponent("pet.json")))
  let data=try Data(contentsOf:packURL.appendingPathComponent(config.atlas.file));let uri="data:image/webp;base64,"+data.base64EncodedString()
  var motionData:[String:String]=[:];var clipData:[String:String]=[:]
  for (id,a) in config.animations {if let m=a.motion {let d=try Data(contentsOf:packURL.appendingPathComponent(m.file));guard d.count==1920*64*4*2 else{throw NSError(domain:"PetPack",code:6,userInfo:[NSLocalizedDescriptionKey:"动作过渡数据损坏：\(id)"])};motionData[id]=d.base64EncodedString()}}
  for (id,a) in config.animations {if let clip=a.clip {clipData[id]="data:image/webp;base64,"+(try Data(contentsOf:packURL.appendingPathComponent(clip.file))).base64EncodedString()}}
  let args=try JSONSerialization.data(withJSONObject:[c,uri,motionData,clipData]);let json=String(data:args,encoding:.utf8)!
  web.evaluateJavaScript("void loadPack(...\(json))"){_,error in if let error=error{self.fail(error.localizedDescription)}}
 }catch{fail(error.localizedDescription)}}
 func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage){
  guard let obj=message.body as? [String:Any],let type=obj["type"] as? String else{return}
  if message.name=="details"{guard message.webView===detailsWeb else{return};if type=="action",let action=obj["action"] as? String{if action=="close"{detailsWindow?.performClose(nil)}else{performInteraction(action)}};if type=="smoke",smoke{finishDetailsSmoke(obj)};return}
  guard message.webView===web else{return}
  if type=="heartbeat"{basics.lastHeartbeat=Date()}
  if smoke,type=="conversation-snapshot"{captureConversationSmoke();return}
  if smoke,type=="conversation-smoke"{finishConversationSmoke(obj);return}
  if type=="chat-motion"{conversation.updateMotion(obj);return}
  if type=="ready"{loaded=true;if !smoke{paused=UserDefaults.standard.bool(forKey:"paused");clickThrough=UserDefaults.standard.bool(forKey:"clickThrough")};setState(config.defaultState ?? "natural_sit");if !smoke{let preference=UserDefaults.standard.string(forKey:"tailMode") ?? "random";setTailMode(preference,persist:false)};if smoke{automatic=false;setRandomBehavior(false,persist:false);setMouseInteraction(false,persist:false);runSmokeChecks()}else{setMouseInteraction(UserDefaults.standard.object(forKey:"mouseInteractionEnabled") == nil ? true:UserDefaults.standard.bool(forKey:"mouseInteractionEnabled"),persist:false);setRandomBehavior(UserDefaults.standard.object(forKey:"randomBehaviorEnabled") == nil ? true:UserDefaults.standard.bool(forKey:"randomBehaviorEnabled"),persist:false);setFocusMode(UserDefaults.standard.bool(forKey:"focusModeEnabled"),persist:false);basics.applyPause();if detailsWeb != nil{sendDetailsProfile()};if CommandLine.arguments.contains("--natural-sit"),config.animations["natural_sit"] != nil{automatic=false;setState("natural_sit")};if CommandLine.arguments.contains("--show-details"){showDetails(nil)};if CommandLine.arguments.contains("--show-ai-settings"){showAISettings(nil)};if CommandLine.arguments.contains("--show-chat") || !UserDefaults.standard.bool(forKey:"chatWelcomeShown"){UserDefaults.standard.set(true,forKey:"chatWelcomeShown");showConversation(nil)}}}
  if type=="focus-motion",let actual=obj["state"] as? String,obj["position"] is Double {
   focusReady=["natural_sit","natural_sit_still"].contains(actual) && obj["transition"] as? Bool != true && obj["paused"] as? Bool != true && (obj["pending"]==nil || obj["pending"] is NSNull)
   if let plan=focusRun,let id=focusRunState{
    if actual==id,config.animations[id]?.evadeMotion != nil,obj["paused"] as? Bool != true,!dragging,menuOpenedAt==nil,!basics.effectivePaused{window.setFrameOrigin(FocusEvadePlanner.position(plan:plan,frame:obj["progress"] as? Double ?? 0,start:0,end:1))}
    else if ["natural_sit","natural_sit_still"].contains(actual),state==id{window.setFrameOrigin(plan.target);focusRun=nil;focusRunState=nil;focusCooldownUntil=Date().addingTimeInterval((config.focusMode?.cooldownMs ?? 2000)/1000);savePosition()}
   }
  }
  if type=="playback",let actual=obj["state"] as? String,config.animations[actual] != nil{if let enabled=obj["randomBehavior"] as? Bool{randomBehaviorEnabled=enabled};if let plan=focusRun,["natural_sit","natural_sit_still"].contains(actual),state==focusRunState{window.setFrameOrigin(plan.target);focusRun=nil;focusRunState=nil;focusCooldownUntil=Date().addingTimeInterval((config.focusMode?.cooldownMs ?? 2000)/1000);savePosition()};state=actual;pendingState=obj["pending"] as? String;if let mode=obj["tailMode"] as? String{tailMode=mode};refreshMenu();refreshDetailsStatus()}
  if smoke,type=="smoke-focus-start",let side=obj["side"] as? String,let screen=NSScreen.main{
   let bounds=screen.visibleFrame;window.setFrameOrigin(NSPoint(x:side=="left" ? bounds.maxX-window.frame.width-24:bounds.minX+24,y:bounds.minY));focusReady=true;focusCooldownUntil = .distantPast
   tickFocusMode(NSPoint(x:focusCatRect().midX,y:focusCatRect().midY),dt:200)
   if let plan=focusRun{web.evaluateJavaScript("window.nativeFocusProbe={origin:\(plan.origin.x),target:\(plan.target.x),width:\(plan.oldRegion.width),direction:'\(plan.direction)'}")}
  }
  if smoke,type=="smoke-focus-cancel"{cancelFocusTravel()}
  if smoke,type=="smoke-focus-position"{web.evaluateJavaScript("window.nativeFocusEnd={x:\(window.frame.minX),y:\(window.frame.minY),running:\(focusRun != nil)}")}
  if smoke,type=="smoke-mode",let enabled=obj["enabled"] as? Bool{setFocusMode(enabled,persist:false)}
  if smoke,type=="smoke-cursor",let x=obj["x"] as? Double,let y=obj["y"] as? Double {
   let frame=window.frame;let width=config.displayFrame?.width ?? 512;let height=config.displayFrame?.height ?? 512
   let px=frame.minX+(x+(width-512)/2)/width*frame.width
   let py=frame.maxY-(y+(config.displayFrame?.paddingTop ?? 0))/height*frame.height
   sendCursor(NSPoint(x:px,y:py),active:true)
  }
  if smoke,type=="smoke-request",let id=obj["state"] as? String{requestState(id)}
  if smoke,type=="smoke-tail",let mode=obj["mode"] as? String{setTailMode(mode,persist:false)}
  if type=="smoke"{smokeChecks=obj;if obj["ok"] as? Bool == true{showDetails(nil)}else{finishSmoke(error:"Animation control checks failed")}}
  if smoke,type=="smoke-state",let id=obj["state"] as? String{setState(id)}

  if type=="error"{fail(obj["message"] as? String ?? "精灵图读取失败")}
 }
 func runSmokeChecks(){
  if CommandLine.arguments.contains("--chat-only"){runConversationSmoke();return}
  let script="""
  void(async()=>{
   const wait=ms=>new Promise(r=>setTimeout(r,ms)),results=[];await wait(100);
   results.push({control:'four actions with a complete still-tail variant, natural sitting default',ok:config.id==='summer-the-cat-v30'&&petDebug.state==='natural_sit'&&Object.keys(config.animations).sort().join(',')==='ears,evade_left,evade_right,groom,look,natural_sit,natural_sit_still,paw_down,paw_down_left,paw_down_right,paw_left,paw_right,paw_up,paw_up_left,paw_up_right,thinking_enter,thinking_exit,thinking_loop,yawn'});
   results.push({control:'updated natural sitting preserves 145 frames at 24 FPS',ok:config.animations.natural_sit.frames===145&&config.animations.natural_sit.fps===24&&petDebug.motionStates===0&&petDebug.clipStates===19});
   playback.setTailMode('moving');setPaused(true);playback.seek(144);await wait(60);const last=ctx.getImageData().data;let area=0;for(let p=3;p<last.length;p+=4)if(last[p]>16)area++;
   results.push({control:'last sitting frame is visible and transparent',ok:petDebug.frame===144&&last.length===1024*640*4&&area>1000&&area<512*640*.8});
   setDirection(-1);await wait(40);const after=ctx.getImageData().data;results.push({control:'nasal pigment never mirrors',ok:last.every((v,i)=>v===after[i])});
   playback.seek(20);await wait(60);const beforeFade=ctx.getImageData().data;setState('look',true);await wait(50);const atFadeStart=ctx.getImageData().data;results.push({control:'GPU transition starts at the exact outgoing frame without opacity dip',ok:playback.transition?.durationMs===160&&beforeFade.every((v,i)=>v===atFadeStart[i])});await wait(80);results.push({control:'paused transition freezes destination and fade progress',ok:playback.elapsed===0&&playback.transition.elapsed===0});setState('natural_sit',true);playback.seek(72);
   playback.seek(72);await wait(40);notify({type:'smoke-request',state:'look'});await wait(100);const boundary=playback.boundary;
   results.push({control:'native menu request queues look without cutting sitting',ok:petDebug.state==='natural_sit'&&petDebug.pending==='look'&&petDebug.frame===72});
   notify({type:'smoke-request',state:'look'});await wait(100);results.push({control:'repeated requests and pause retain current cycle boundary',ok:playback.boundary===boundary&&petDebug.state==='natural_sit'&&petDebug.frame===72});
   const seen=[],original=playback.markPresented.bind(playback);playback.markPresented=()=>{seen.push({state:playback.state,frame:playback.frame});original()};
   playback.elapsed=boundary-100;setPaused(false);await wait(350);results.push({control:'look starts only after the final sitting frame is displayed',ok:petDebug.state==='look'&&petDebug.pending===null&&seen.some(v=>v.state==='natural_sit'&&v.frame===144)&&seen.some(v=>v.state==='look'&&v.frame===config.animations.look.playbackRange.startFrame)});
   setPaused(true);playback.seek(192);await wait(60);results.push({control:'look keeps original source and trims redundant still ends',ok:petDebug.state==='look'&&petDebug.frame===187&&config.animations.look.fps===24});
   playback.elapsed=playback.duration+1;setPaused(false);await wait(150);results.push({control:'look finishes and returns to natural sitting',ok:petDebug.state==='natural_sit'});
   setPaused(true);await wait(40);const frozen=petDebug.frame;await wait(100);results.push({control:'pause freezes progress',ok:petDebug.frame===frozen});
   results.push({control:'old actions remain unavailable',ok:setState('walk')===false&&setState('front_sit')===false});
   setState('natural_sit',true);setPaused(true);playback.seek(40);await wait(50);notify({type:'smoke-tail',mode:'still'});await wait(100);
   results.push({control:'native tail control queues intact still-tail video',ok:petDebug.state==='natural_sit'&&petDebug.pending==='natural_sit_still'&&petDebug.tailMode==='still'&&petDebug.frame===40});
   playback.elapsed=playback.boundary-100;setPaused(false);await wait(350);results.push({control:'still tail starts after current sitting finishes',ok:petDebug.state==='natural_sit_still'&&petDebug.pending===null});
   setPaused(true);notify({type:'smoke-request',state:'look'});await wait(100);playback.elapsed=playback.boundary-100;setPaused(false);await wait(350);results.push({control:'look waits for still-tail sitting too',ok:petDebug.state==='look'});
   setPaused(true);playback.seek(192);playback.elapsed=playback.duration+1;setPaused(false);await wait(150);results.push({control:'look returns to selected still-tail mode',ok:petDebug.state==='natural_sit_still'});
   setPaused(true);notify({type:'smoke-tail',mode:'random'});await wait(100);playback.randomCycles=1;playback.elapsed=playback.duration-100;setPaused(false);await wait(350);results.push({control:'random tail mode switches complete idle clips',ok:petDebug.state==='natural_sit'&&petDebug.tailMode==='random'});
   setPaused(true);setTailMode('still');await wait(50);setState('natural_sit_still',true);playback.seek(40);await wait(60);notify({type:'smoke-request',state:'yawn'});await wait(100);const yawnBoundary=playback.boundary;
   results.push({control:'native menu yawn waits for complete still-tail sitting',ok:petDebug.state==='natural_sit_still'&&petDebug.pending==='yawn'&&petDebug.frame===40});
   setTailMode('moving');await wait(100);results.push({control:'tail setting preserves queued yawn priority',ok:petDebug.pending==='yawn'&&playback.boundary===yawnBoundary});
   playback.elapsed=yawnBoundary-100;setPaused(false);await wait(350);results.push({control:'yawn begins after complete sitting with source frames and rate',ok:petDebug.state==='yawn'&&petDebug.pending===null&&config.animations.yawn.frames===146&&config.animations.yawn.fps===24&&config.animations.yawn.loop===false});
   setPaused(true);playback.seek(75);await wait(60);const yawnPixels=ctx.getImageData().data;let solid=-1,empty=-1;for(let i=0;i<yawnPixels.length;i+=4){if(solid<0&&yawnPixels[i+3]>200)solid=i/4;if(empty<0&&yawnPixels[i+3]===0)empty=i/4;if(solid>=0&&empty>=0)break;}results.push({control:'hand cursor hits visible cat pixels only',ok:solid>=0&&empty>=0&&catHitTest(solid%canvas.width,Math.floor(solid/canvas.width))&&!catHitTest(empty%canvas.width,Math.floor(empty/canvas.width))&&!catHitTest(-1,0)});let ya=0;for(let p=3;p<yawnPixels.length;p+=4)if(yawnPixels[p]>16)ya++;results.push({control:'open-mouth yawning frame renders transparent cat',ok:petDebug.frame===75&&ya>1000&&ya<512*640*.8});
   playback.seek(config.animations.yawn.frames-1);playback.elapsed=playback.duration+1;setPaused(false);await wait(150);results.push({control:'yawn plays once and returns to chosen sitting mode',ok:petDebug.state==='natural_sit'&&petDebug.tailMode==='moving'});
   setPaused(true);setState('natural_sit',true);playback.seek(40);await wait(60);notify({type:'smoke-request',state:'groom'});await wait(100);const groomBoundary=playback.boundary;
   results.push({control:'native menu grooming waits for complete sitting',ok:petDebug.state==='natural_sit'&&petDebug.pending==='groom'&&petDebug.frame===40});
   setTailMode('still');await wait(60);results.push({control:'tail changes preserve queued grooming',ok:petDebug.pending==='groom'&&playback.boundary===groomBoundary});
   playback.elapsed=groomBoundary-100;setPaused(false);await wait(350);results.push({control:'grooming preserves original 24 FPS source with shorter still ends',ok:petDebug.state==='groom'&&config.animations.groom.frames===193&&config.animations.groom.fps===24&&config.animations.groom.loop===false});
   setPaused(true);playback.seek(96);await wait(60);const gp=ctx.getImageData().data;let ga=0;for(let p=3;p<gp.length;p+=4)if(gp[p]>16)ga++;results.push({control:'grooming frame renders transparent cat',ok:petDebug.frame===96&&ga>1000&&ga<512*640*.8});
   playback.seek(192);playback.elapsed=playback.duration+1;setPaused(false);await wait(150);results.push({control:'grooming returns to selected still-tail mode',ok:petDebug.state==='natural_sit_still'});
   setPaused(true);setState('natural_sit',true);setTailMode('moving');setRandomBehavior(true);playback.behaviorCycles=1;playback.random=()=>0;const autoStart=playback.automaticActionCount;playback.elapsed=playback.duration-100;setPaused(false);await wait(350);results.push({control:'random ear action starts only at the full sitting boundary',ok:petDebug.state==='ears'&&petDebug.randomBehavior&&playback.automaticActionCount===autoStart+1&&config.animations.ears.frames===146&&config.animations.ears.fps===24});
   setPaused(true);playback.seek(145);playback.elapsed=playback.duration+1;setPaused(false);await wait(160);results.push({control:'ear movement completes once and returns to sitting',ok:petDebug.state==='natural_sit'&&playback.behaviorCycles>=2&&playback.behaviorCycles<=5});
   setRandomBehavior(false);setMouseInteraction(true);setTeaserMode(true);setTailMode('moving');setState('natural_sit',true);interaction.cooldownUntil=0;notify({type:'smoke-cursor',x:448,y:258});await wait(420);results.push({control:'global macOS cursor coordinates select an intact right-paw gesture',ok:petDebug.state==='paw_right'&&petDebug.interactionCount===1&&config.animations.paw_right.interactionOnly===true});
   const locked=petDebug.state;notify({type:'smoke-cursor',x:288,y:78});await wait(120);results.push({control:'mouse direction changes never interrupt an extended paw',ok:petDebug.state===locked&&petDebug.interactionCount===1});
   setPaused(true);playback.seek(config.animations.paw_right.frames-1);playback.elapsed=playback.duration+1;setPaused(false);await wait(420);results.push({control:'paw returns to grounded idle and enters cooldown',ok:petDebug.state==='natural_sit'&&interaction.cooldownUntil>interaction.now});
   setTeaserMode(false);setMouseInteraction(false);setTailMode('random');setState('natural_sit',true);setPaused(false);await wait(1100);const intervals=petDebug.intervals.slice(-60).sort((a,b)=>a-b),p95=intervals[Math.floor(intervals.length*.95)];results.push({control:'native frame pacing',intervalP95Ms:p95,ok:intervals.length>=40&&p95<35});
   setState('natural_sit',true);setPaused(false);setMouseInteraction(true);setRandomBehavior(true);notify({type:'smoke-mode',enabled:true});await wait(250);
   results.push({control:'focus mode disables random actions and paw interaction',ok:focusEnabled&&!interaction.enabled&&!playback.randomBehavior});
   for(const side of ['left','right']){
    const id='evade_'+side;setState('natural_sit',true);await wait(250);window.nativeFocusProbe=null;notify({type:'smoke-focus-start',side});await wait(350);
    results.push({control:id+' native hover selects available side',ok:playback.state===id&&nativeFocusProbe?.direction===side});
    setPaused(true);const frozen=playback.motionProgress;await wait(100);results.push({control:id+' travel pauses with animation',ok:playback.motionProgress===frozen});setPaused(false);
    for(let i=0;i<80&&!playback.isIdle();i++)await wait(100);
    notify({type:'smoke-focus-position'});await wait(100);
    results.push({control:id+' native window clears old cat region and sits at target',probe:nativeFocusProbe,end:nativeFocusEnd,animation:playback.state,ok:playback.isIdle()&&!nativeFocusEnd.running&&Math.abs(nativeFocusEnd.x-nativeFocusProbe.target)<=.5&&Math.abs(nativeFocusEnd.x-nativeFocusProbe.origin)>nativeFocusProbe.width});
   }
   setState('natural_sit',true);await wait(250);notify({type:'smoke-focus-start',side:'right'});await wait(350);notify({type:'smoke-focus-cancel'});await wait(300);results.push({control:'cancelled focus travel settles into sitting instead of running in place',ok:playback.isIdle()});
   notify({type:'smoke-mode',enabled:false});await wait(250);results.push({control:'play mode restores saved interactive preferences',ok:!focusEnabled&&interaction.enabled&&playback.randomBehavior});
   setRandomBehavior(false);setMouseInteraction(false);
   notify({type:'smoke',ok:results.every(r=>r.ok),results});
  })().catch(e=>notify({type:'smoke',ok:false,message:String(e)}));
  """
  web.evaluateJavaScript(script){_,error in if let error=error{self.finishSmoke(error:error.localizedDescription)}}
 }
 func setState(_ id:String){guard config.animations[id] != nil else{return};state=id;pendingState=nil;web?.evaluateJavaScript("setState('\(id)',true)");refreshMenu();refreshDetailsStatus()}
 func updateTickTimer(_ interval:Double){
  if timer?.isValid==true,tickInterval==interval{return};timer?.invalidate();tickInterval=interval
  timer=Timer.scheduledTimer(withTimeInterval:interval,repeats:true){[weak self]_ in self?.tick()};RunLoop.main.add(timer!,forMode:.common)
 }
 func tick(){
  conversation.updatePosition()
  floatingMenu.update()
  if !smoke{probeCatHit();cursorStyles.update()}
  teaserCursor.update()
  guard menuOpenedAt==nil,!basics.effectivePaused else{lastTick=Date();return}
  let now=Date(),dt=min(50,max(0,now.timeIntervalSince(lastTick)*1000));lastTick=now;if !smoke{if focusModeEnabled{restorePettingCursor();tickFocusMode(NSEvent.mouseLocation,dt:dt);updateFocusMenu()}else{updatePettingCursor(NSEvent.mouseLocation)}};guard loaded,!smoke,!focusModeEnabled,!cursorSendInFlight,lastTick.timeIntervalSince(lastCursorSent)>=1.0/30 else{return};lastCursorSent=lastTick
  sendCursor(NSEvent.mouseLocation,active:teaserCursor.enabled && mouseInteractionEnabled && !paused && !dragging && menuOpenedAt==nil && window.isVisible)
 }
 // The window provides a native cursor surface over the interaction ellipse.
 // Replacing the cursor avoids foreground-only global cursor hiding.
 @objc func toggleTeaser(){teaserCursor.toggle()}
 func setupPettingCursor(){
  pettingHandCursor=cursorStyles.pat
  let panel=PetWindow(contentRect:NSRect(x:0,y:0,width:40,height:40),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  panel.isOpaque=false;panel.backgroundColor = NSColor.white.withAlphaComponent(0.01);panel.hasShadow=false;panel.ignoresMouseEvents=false;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false;panel.acceptsMouseMovedEvents=true
  panel.level=NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+1);panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
  let view=PettingCursorView(frame:panel.contentView!.bounds);view.owner=self;view.autoresizingMask=[.width,.height];panel.contentView=view;pettingCursorWindow=panel
 }
 func setupStatusSummon(){
  guard let button=status.button else{return};button.toolTip="悬停召唤猫咪；点击打开菜单";button.setAccessibilityLabel("夏天 · 悬停召唤，点击菜单")
  let view=StatusSummonHoverView(frame:button.bounds);view.owner=self;view.autoresizingMask=[.width,.height];button.addSubview(view);statusSummonView=view
 }
 func summonFromMenuBar(){
  guard window != nil,!basics.systemSuspended,menuOpenedAt==nil else{return}
  if basics.userHidden || basics.fullscreenHidden{cancelFocusTravel()}
  basics.fullscreenRevealRequested=true;basics.fullscreenHidden=false
  if !basics.positionLocked,let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}),!screen.visibleFrame.intersects(window.frame){window.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX-window.frame.width/2,y:screen.visibleFrame.minY));savePosition()}
  constrain();basics.showFromAnotherInstance()
 }
 func setupFocusMenu(){
  let panel=PetWindow(contentRect:NSRect(x:0,y:0,width:150,height:174),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  panel.isOpaque=false;panel.backgroundColor=NSColor.white.withAlphaComponent(0.01);panel.hasShadow=false;panel.ignoresMouseEvents=false;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
  panel.level=NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+1);panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
  let view=FocusMenuView(frame:panel.contentView!.bounds);view.owner=self;view.autoresizingMask=[.width,.height];panel.contentView=view;focusMenuWindow=panel
 }
 func updateFocusMenu(){
  guard let panel=focusMenuWindow else{return}
  if menuOpenedAt != nil{return}
  guard focusModeEnabled,loaded,window.isVisible,!basics.systemSuspended,!basics.userHidden,!basics.fullscreenHidden else{panel.orderOut(nil);return}
  let rect=focusCatRect();guard basics.canReceivePointer(NSPoint(x:rect.midX,y:rect.midY)) else{panel.orderOut(nil);return};if panel.frame != rect{panel.setFrame(rect,display:false)};if !panel.isVisible{panel.orderFrontRegardless()}
 }
 func isNearCat(_ point:NSPoint)->Bool{
  guard !conversation.motionActive,loaded,!focusModeEnabled,mouseInteractionEnabled,!paused,!dragging,menuOpenedAt==nil,window.isVisible,let policy=config.mouseInteraction,policy.anchor.count==2,policy.reach.count==2,policy.reach.allSatisfy({$0>0}) else{return false}
  if let details=detailsWindow,details.isVisible,details.frame.contains(point){return false}
  let f=window.frame,x=(point.x-f.minX)*(config.displayFrame?.width ?? 512)/f.width,y=(f.maxY-point.y)*(config.displayFrame?.height ?? 512)/f.height
  return hypot((x-policy.anchor[0])/policy.reach[0],(y-policy.anchor[1])/policy.reach[1])<=1
 }
 func isOnCat(_ point:NSPoint)->Bool{
  guard isNearCat(point) else{return false}
  if let mask=bodyMask{
   let frame=window.frame,x=Int(floor((point.x-frame.minX)*(config.displayFrame?.width ?? 512)/frame.width))-bodyMaskX,y=Int(floor((frame.maxY-point.y)*(config.displayFrame?.height ?? 512)/frame.height))-bodyMaskY
   guard x>=0,y>=0,x<bodyMaskSize,y<bodyMaskSize else{return false}
   let bit=y*bodyMaskSize+x;return bit/8<mask.count && mask[bit/8] & UInt8(1<<(bit%8)) != 0
  }
  return bodyHit && hypot(point.x-bodyHitPoint.x,point.y-bodyHitPoint.y)<=4
 }
 func probeCatHit(){
  let point=NSEvent.mouseLocation
  guard loaded,window.isVisible,window.frame.contains(point) else{bodyHit=false;bodyMask=nil;return}
  guard !hitProbeInFlight,Date().timeIntervalSince(lastHitProbe)>=1.0/30 else{return}
  let frame=window.frame,x=(point.x-frame.minX)*(config.displayFrame?.width ?? 512)/frame.width,y=(frame.maxY-point.y)*(config.displayFrame?.height ?? 512)/frame.height
  hitProbeInFlight=true;lastHitProbe=Date()
  web.evaluateJavaScript("window.catHitRegion(\(x),\(y))"){[weak self] value,error in
   guard let self=self else{return};self.hitProbeInFlight=false;self.bodyHit=false;self.bodyHitPoint=point
   guard error==nil,self.window.frame==frame,let result=value as? [String:Any],let encoded=result["data"] as? String,let data=Data(base64Encoded:encoded),let size=result["size"] as? Int,size>0,size<=128,data.count==(size*size+7)/8 else{self.bodyMask=nil;return}
   self.bodyMask=data;self.bodyMaskX=result["x"] as? Int ?? 0;self.bodyMaskY=result["y"] as? Int ?? 0;self.bodyMaskSize=size
  }
 }
 func updatePettingCursor(_ point:NSPoint){
  guard (teaserCursor.enabled ? isNearCat(point):isOnCat(point)),basics.canReceivePointer(point),let panel=pettingCursorWindow,let policy=config.mouseInteraction else{restorePettingCursor();return}
  let f=window.frame,cx=f.minX+policy.anchor[0]/(config.displayFrame?.width ?? 512)*f.width,cy=f.maxY-policy.anchor[1]/(config.displayFrame?.height ?? 512)*f.height,rx=policy.reach[0]/(config.displayFrame?.width ?? 512)*f.width,ry=policy.reach[1]/(config.displayFrame?.height ?? 512)*f.height
  let cursorFrame=NSRect(x:cx-rx,y:cy-ry,width:rx*2,height:ry*2)
  if panel.frame != cursorFrame{panel.setFrame(cursorFrame,display:false);panel.invalidateCursorRects(for:panel.contentView!)}
  if !panel.isVisible{
   if !NSApp.isActive{cursorPreviousApp=NSWorkspace.shared.frontmostApplication;NSApp.activate(ignoringOtherApps:true)}
   window.disableCursorRects();panel.orderFrontRegardless();panel.invalidateCursorRects(for:panel.contentView!)
  }
  pettingCursorActive=true;pettingHandCursor?.set()
 }
 func restorePettingCursor(restoreFocus:Bool=true){
  pettingCursorWindow?.orderOut(nil)
  if pettingCursorActive{pettingCursorActive=false;window?.enableCursorRects();(window?.frame.contains(NSEvent.mouseLocation)==true ? PetCursorStyles.arrow:NSCursor.arrow).set()}
  if !smoke{cursorStyles.applyDefault(at:NSEvent.mouseLocation)}
  // Keep the pet active while its menu or drag owns mouse input.
  if restoreFocus,menuOpenedAt==nil,!dragging{let previous=cursorPreviousApp;cursorPreviousApp=nil;if NSApp.isActive,let previous=previous,!previous.isTerminated{previous.activate(options:[.activateIgnoringOtherApps])}}
 }
 func applicationWillTerminate(_ notification:Notification){statusSummonView?.cancel();basics.stop();if let monitor=contextMenuMonitor{NSEvent.removeMonitor(monitor)};if let monitor=cursorEventMonitor{NSEvent.removeMonitor(monitor)};focusMenuWindow?.orderOut(nil);restorePettingCursor()}
 func sendCursor(_ point:NSPoint,active:Bool){
  guard loaded,let frame=window?.frame,frame.width>0,frame.height>0 else{return}
  let active=active && (smoke || teaserCursor.enabled)
  let x=(point.x-frame.minX)*(config.displayFrame?.width ?? 512)/frame.width,y=(frame.maxY-point.y)*(config.displayFrame?.height ?? 512)/frame.height
  cursorSendInFlight=true;web.evaluateJavaScript("updateMousePointer(\(x),\(y),\(active))"){_,_ in self.cursorSendInFlight=false}
 }
 func clearCursorInteraction(){restorePettingCursor(restoreFocus:false);web?.evaluateJavaScript("clearMouseInteraction()")}
 func setMouseInteraction(_ enabled:Bool,persist:Bool=true){mouseInteractionEnabled=enabled;if !enabled{restorePettingCursor()};if persist{UserDefaults.standard.set(enabled,forKey:"mouseInteractionEnabled")};web?.evaluateJavaScript("setMouseInteraction(\(enabled))");refreshMenu()}
 @objc func toggleMouseInteraction(){guard !focusModeEnabled else{return};setMouseInteraction(!mouseInteractionEnabled)}
 func pet(){performInteraction("play")}
 func setFocusMode(_ enabled:Bool,persist:Bool=true){
  focusModeEnabled=enabled;focusReady=false;focusHoverMs=0;restorePettingCursor();window.ignoresMouseEvents=enabled || clickThrough
  if persist{UserDefaults.standard.set(enabled,forKey:"focusModeEnabled")}
  web.evaluateJavaScript("setFocusMode(\(enabled))")
  if enabled{setRandomBehavior(false,persist:false);setMouseInteraction(false,persist:false)}
  if !enabled{let defaults=UserDefaults.standard;setRandomBehavior(defaults.object(forKey:"randomBehaviorEnabled")==nil ? true:defaults.bool(forKey:"randomBehaviorEnabled"),persist:false);setMouseInteraction(defaults.object(forKey:"mouseInteractionEnabled")==nil ? true:defaults.bool(forKey:"mouseInteractionEnabled"),persist:false)}
  updateFocusMenu();refreshMenu()
 }
 @objc func selectCompanionMode(){setFocusMode(false)}
 @objc func selectFocusMode(){setFocusMode(true)}
 func cancelFocusTravel(){if focusRun != nil{web?.evaluateJavaScript("window.cancelFocusEvade?.()")};focusRun=nil;focusRunState=nil;focusHoverMs=0;focusCooldownUntil=Date().addingTimeInterval(2)}
 func focusCatRect()->NSRect{
  let f=window.frame,rect=config.focusMode?.triggerRect ?? [392,224,692,572],w=config.displayFrame?.width ?? 1024,h=config.displayFrame?.height ?? 640
  return NSRect(x:f.minX+rect[0]/w*f.width,y:f.maxY-rect[3]/h*f.height,width:(rect[2]-rect[0])/w*f.width,height:(rect[3]-rect[1])/h*f.height)
 }
 func tickFocusMode(_ pointer:NSPoint,dt:Double){
  guard !conversation.motionActive,loaded,!basics.effectivePaused,!basics.positionLocked,!dragging,menuOpenedAt==nil,NSEvent.pressedMouseButtons & 2 == 0,focusRun==nil,focusReady,Date()>=focusCooldownUntil else{focusHoverMs=0;return}
  let cat=focusCatRect();guard cat.contains(pointer),basics.canReceivePointer(pointer) else{focusHoverMs=0;return};focusHoverMs+=dt
  guard focusHoverMs>=(config.focusMode?.dwellMs ?? 100),let screen=NSScreen.screens.first(where:{$0.visibleFrame.contains(NSPoint(x:cat.midX,y:cat.midY))}) ?? NSScreen.main,
   let plan=FocusEvadePlanner.plan(window:window.frame,cat:cat,screen:screen.visibleFrame,clearance:config.focusMode?.minimumClearance ?? 24,margin:config.focusMode?.screenMargin ?? 12,fraction:config.focusMode?.preferredTravelFraction ?? 0.22) else{return}
  let id="evade_"+plan.direction;guard config.animations[id] != nil else{return};focusHoverMs=0;focusReady=false;focusRun=plan;focusRunState=id
  web.evaluateJavaScript("beginFocusEvade('\(id)')"){value,error in if error != nil || value as? Bool != true{self.focusRun=nil;self.focusRunState=nil;self.focusCooldownUntil=Date().addingTimeInterval(0.3)}}
 }
 func makeMenu()->NSMenu{
  let m=NSMenu();m.autoenablesItems=false;m.delegate=self;let title=NSMenuItem(title:"\(config?.name ?? "Summer The Cat") · 桌面宠物",action:nil,keyEquivalent:"");title.isEnabled=false;m.addItem(title);m.addItem(.separator())
  add(m,"和夏天聊聊…",#selector(showConversation(_:)));add(m,"AI 连接设置…",#selector(showAISettings(_:)));add(m,"宠物详情…",#selector(showDetails(_:)));add(m,"逗猫棒光标",#selector(toggleTeaser),teaserCursor.enabled);m.addItem(.separator())
  let modes=NSMenu();add(modes,"玩耍模式",#selector(selectCompanionMode),!focusModeEnabled);add(modes,"专心模式",#selector(selectFocusMode),focusModeEnabled);let modesItem=NSMenuItem(title:"桌宠模式",action:nil,keyEquivalent:"");modesItem.submenu=modes;m.addItem(modesItem)
  let controls=NSMenu();add(controls,"播放",#selector(playAnimation));add(controls,"暂停",#selector(togglePause));add(controls,"重新播放",#selector(replayAnimation));let controlItem=NSMenuItem(title:"播放控制",action:nil,keyEquivalent:"");controlItem.submenu=controls;m.addItem(controlItem)
  let actions=NSMenu();for id in actionIDs{guard config.animations[id] != nil else{continue};let item=NSMenuItem(title:(config?.animations[id]?.label ?? id)+(pendingState==id ? "（等待当前动作播完）":""),action:#selector(chooseState(_:)),keyEquivalent:"");item.representedObject=id;item.target=self;item.state=(state==id || (id=="natural_sit" && state=="natural_sit_still")) ? .on:.off;actions.addItem(item)};let actionItem=NSMenuItem(title:"动作选择",action:nil,keyEquivalent:"");actionItem.submenu=actions;m.addItem(actionItem)
  if config.animations["natural_sit_still"] != nil{let tails=NSMenu();for (label,mode) in [("随机摆动","random"),("摆动","moving"),("保持不动","still")]{let item=NSMenuItem(title:label,action:#selector(chooseTailMode(_:)),keyEquivalent:"");item.target=self;item.representedObject=mode;item.state=tailMode==mode ? .on:.off;tails.addItem(item)};let item=NSMenuItem(title:"静坐时的尾巴"+(pendingState=="natural_sit_still" || pendingState=="natural_sit" ? "（等待当前动作播完）":""),action:nil,keyEquivalent:"");item.submenu=tails;m.addItem(item)}
  m.addItem(.separator());add(m,"随机行为",#selector(toggleRandomBehavior),randomBehaviorEnabled);add(m,"鼠标互动",#selector(toggleMouseInteraction),mouseInteractionEnabled);add(m,"暂停",#selector(togglePause),paused);add(m,"鼠标穿透",#selector(toggleClickThrough),clickThrough || focusModeEnabled)
  for item in m.items where [#selector(toggleRandomBehavior),#selector(toggleMouseInteraction),#selector(toggleClickThrough)].contains(item.action ?? #selector(quit)){item.isEnabled = !focusModeEnabled}
  let sizes=NSMenu();for (label,scale) in [("小 · 192",0.75),("中 · 256",1.0),("大 · 320",1.25)]{let i=NSMenuItem(title:label,action:#selector(changeSize(_:)),keyEquivalent:"");i.target=self;i.representedObject=scale;sizes.addItem(i)}
  let sizeItem=NSMenuItem(title:"显示大小",action:nil,keyEquivalent:"");sizeItem.submenu=sizes;m.addItem(sizeItem)
  let settings=NSMenuItem(title:"桌宠设置",action:nil,keyEquivalent:"");settings.submenu=basics.settingsMenu();m.addItem(settings);add(m,"回到屏幕底部",#selector(resetAction));add(m,"导入宠物包文件夹…",#selector(importPack));add(m,"恢复内置宠物",#selector(restorePack));m.addItem(.separator());add(m,"退出",#selector(quit));if conversation.motionActive{for i in m.items where ["动作选择","静坐时的尾巴","播放控制","随机行为","鼠标互动","桌宠模式"].contains(i.title){i.isEnabled=false}};return m
 }
 func add(_ menu:NSMenu,_ title:String,_ action:Selector,_ checked:Bool=false){let i=NSMenuItem(title:title,action:action,keyEquivalent:"");i.target=self;i.state=checked ? .on:.off;menu.addItem(i)}
 func beginMenuTracking(){
  guard menuOpenedAt==nil else{return};statusSummonView?.cancel();menuOpenedAt=Date();focusHoverMs=0
  // Keep the originating input window alive throughout native menu tracking.
  web.evaluateJavaScript("clearMouseInteraction();setPaused(true)")
 }
 func endMenuTracking(){
  guard let opened=menuOpenedAt else{return};deadline=deadline.addingTimeInterval(Date().timeIntervalSince(opened));menuOpenedAt=nil;lastTick=Date();focusHoverMs=0;focusCooldownUntil=Date().addingTimeInterval(0.5)
  basics.applyPause()
  DispatchQueue.main.async{[weak self] in guard let self=self,self.menuOpenedAt==nil else{return};self.refreshMenu();self.updateFocusMenu()}
 }
 func showContextMenu(_ event:NSEvent,from view:NSView){
  guard menuOpenedAt==nil,!contextMenuShowing else{return};contextMenuShowing=true;beginMenuTracking()
  let menu=makeMenu();activeContextMenu=menu;NSMenu.popUpContextMenu(menu,with:event,for:view)
 }
 func menuWillOpen(_ menu:NSMenu){beginMenuTracking()}
 func menuDidClose(_ menu:NSMenu){if let active=activeContextMenu,menu !== active{return};contextMenuShowing=false;activeContextMenu=nil;endMenuTracking()}
 func refreshMenu(){
  guard menuOpenedAt==nil,!contextMenuShowing,!menuRefreshQueued else{return};menuRefreshQueued=true
  DispatchQueue.main.async{[weak self] in guard let self=self else{return};self.menuRefreshQueued=false;guard self.menuOpenedAt==nil,!self.contextMenuShowing else{return};self.status?.menu=self.makeMenu()}
 }
 func requestState(_ id:String){guard config.animations[id] != nil else{return};web.evaluateJavaScript("requestState('\(id)')")}
 @objc func chooseState(_ sender:NSMenuItem){automatic=false;requestState(sender.representedObject as! String)}
 func setTailMode(_ mode:String,persist:Bool=true){guard ["random","moving","still"].contains(mode),config.animations["natural_sit_still"] != nil else{return};if persist{UserDefaults.standard.set(mode,forKey:"tailMode")};web.evaluateJavaScript("setTailMode('\(mode)')")}
 @objc func chooseTailMode(_ sender:NSMenuItem){guard let mode=sender.representedObject as? String else{return};setTailMode(mode)}
 func setRandomBehavior(_ enabled:Bool,persist:Bool=true){randomBehaviorEnabled=enabled;if persist{UserDefaults.standard.set(enabled,forKey:"randomBehaviorEnabled")};web.evaluateJavaScript("setRandomBehavior(\(enabled))");refreshMenu()}
 @objc func toggleRandomBehavior(){guard !focusModeEnabled else{return};setRandomBehavior(!randomBehaviorEnabled)}
 @objc func togglePause(){paused.toggle();if paused{restorePettingCursor()};basics.applyPause();if !smoke{UserDefaults.standard.set(paused,forKey:"paused")};refreshMenu();refreshDetailsStatus()}
 @objc func toggleClickThrough(){guard !focusModeEnabled else{return};clickThrough.toggle();window.ignoresMouseEvents=clickThrough || focusModeEnabled;if !smoke{UserDefaults.standard.set(clickThrough,forKey:"clickThrough")};refreshMenu()}
 @objc func changeSize(_ sender:NSMenuItem){cancelFocusTravel();resize(to:sender.representedObject as! Double);constrain();savePosition()}
 func resize(to scale:Double){let origin=window.frame.origin;window.setFrame(NSRect(origin:origin,size:NSSize(width:256*scale*(config.displayFrame?.width ?? 512)/512,height:256*scale*(config.displayFrame?.height ?? 512)/512)),display:true);if !smoke{UserDefaults.standard.set(scale,forKey:"petScale")}}
 @objc func resetAction(){cancelFocusTravel();resetPosition();savePosition()}
 func resetPosition(){guard let screen=window.screen ?? NSScreen.main else{return};let r=screen.visibleFrame;window.setFrameOrigin(NSPoint(x:r.midX-window.frame.width/2,y:r.minY))}
 func constrain(){guard let screen=DesktopControls.screenFor(window.frame,NSScreen.screens.map{$0.visibleFrame}) else{return};let current=window.frame;let fit=DesktopControls.constrained(current,to:screen);if fit.size != current.size{let ratio=min(fit.width/current.width,fit.height/current.height);window.setContentSize(NSSize(width:current.width*ratio,height:current.height*ratio))};window.setFrameOrigin(DesktopControls.constrained(window.frame,to:screen).origin)}
 func savePosition(){guard !smoke else{return};UserDefaults.standard.set(window.frame.minX,forKey:"petX");UserDefaults.standard.set(window.frame.minY,forKey:"petY")}
 @objc func importPack(){let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.allowsMultipleSelection=false;panel.message="选择包含 pet.json 和 spritsheet.webp 的文件夹";panel.level = .floating
  guard panel.runModal() == .OK,let url=panel.url else{return};let oldConfig=config,oldURL=packURL
  do{try readPack(url);basics.recoveryCount=0;reloadPetDocument();refreshMenu()}catch{config=oldConfig;packURL=oldURL;fail(error.localizedDescription)}
 }
 @objc func restorePack(){do{try readPack(Bundle.main.resourceURL!.appendingPathComponent("pet-pack"));basics.recoveryCount=0;reloadPetDocument()}catch{fail(error.localizedDescription)}}
 @objc func playAnimation(){performInteraction("play")}
 @objc func replayAnimation(){performInteraction("replay")}
 func performInteraction(_ action:String){
  let feedback:String
  switch action{
  case "play":paused=false;feedback="继续播放\(config.animations[state]?.label ?? state)。"
  case "pause":paused=true;feedback="已暂停\(config.animations[state]?.label ?? state)。"
  case "replay":paused=false;setState(state);feedback="从头播放\(config.animations[state]?.label ?? state)。"
  default:return
  }
  basics.applyPause();if !smoke{UserDefaults.standard.set(paused,forKey:"paused")};refreshMenu();refreshDetailsStatus()
  if let data=try? JSONSerialization.data(withJSONObject:[feedback]),let args=String(data:data,encoding:.utf8){detailsWeb?.evaluateJavaScript("window.showFeedback?.(...\(args))")}
 }
 func detailsStatus()->String{let waiting:String;if let pending=pendingState{waiting=" · 等待当前动作播完后"+((pending=="natural_sit" || pending=="natural_sit_still") ? "切换尾巴模式":(config.animations[pending]?.label ?? pending))}else{waiting=""};return (paused ? "已暂停 · ":"正在 · ")+(config.animations[state]?.label ?? state)+waiting}
 func refreshDetailsStatus(){guard let data=try? JSONSerialization.data(withJSONObject:[detailsStatus()]),let args=String(data:data,encoding:.utf8)else{return};detailsWeb?.evaluateJavaScript("window.updatePetStatus?.(...\(args))")}
 func detailsProfile()->[String:Any]{
  let summer=config.id.hasPrefix("summer-the-cat"),nickname=summer ? "夏天":config.name
  var portrait=""
  if let main=config.main,main==URL(fileURLWithPath:main).lastPathComponent,let image=try? Data(contentsOf:packURL.appendingPathComponent(main)),image.count<5_000_000,NSImage(data:image) != nil{portrait="data:image/png;base64,"+image.base64EncodedString()}
  if portrait.isEmpty,let data=try? Data(contentsOf:packURL.appendingPathComponent(config.atlas.file)),let source=CGImageSourceCreateWithData(data as CFData,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil),let row=config.animations[config.defaultState ?? "natural_sit"]?.row,let crop=image.cropping(to:CGRect(x:0,y:row*config.atlas.frameHeight,width:config.atlas.frameWidth,height:config.atlas.frameHeight)),let png=NSBitmapImageRep(cgImage:crop).representation(using:.png,properties:[:]){portrait="data:image/png;base64,"+png.base64EncodedString()}
  var profile:[String:Any]
  if summer,let url=Bundle.main.resourceURL?.appendingPathComponent("summer-profile.json"),let data=try? Data(contentsOf:url),let stored=try? JSONSerialization.jsonObject(with:data) as? [String:Any]{profile=stored}else{
   profile=["nickname":nickname,"introduction":config.description ?? "在你的桌面上，陪你度过工作与休息的每一刻。","tags":["桌面宠物","陪伴每一天"],"features":[["title":"你的桌面伙伴","text":"在工作和休息之间，留一点时间陪伴。"],["title":"自己的日常节奏","text":"通过右键菜单选择视频动作和控制播放。"],["title":"随时互动","text":"轻点继续播放，拖动换位置，右键查看更多功能。"]]]
  }
  profile["name"]=config.name;profile["actions"]=actionIDs.compactMap{config.animations[$0]?.label};profile["available"]=Array(config.animations.keys);profile["defaultState"]=config.defaultState ?? "natural_sit";profile["portrait"]=portrait;profile["status"]=detailsStatus();return profile
 }
 @objc func showDetails(_ sender:Any?){
  if detailsWindow==nil{
   guard let resource=Bundle.main.resourceURL,let html=try? String(contentsOf:resource.appendingPathComponent("pet-details.html"),encoding:.utf8)else{fail("宠物详情页无法读取");return}
   let panel=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);panel.isReleasedWhenClosed=false;panel.minSize=NSSize(width:580,height:500);panel.title="\(config.name) · 宠物详情";panel.backgroundColor=NSColor(red:0.965,green:0.961,blue:0.941,alpha:1);panel.center()
   let wc=WKWebViewConfiguration();wc.userContentController.add(self,name:"details");let view=WKWebView(frame:panel.contentView!.bounds,configuration:wc);view.autoresizingMask=[.width,.height];view.navigationDelegate=self;panel.contentView=view;detailsWindow=panel;detailsWeb=view;view.loadHTMLString(html,baseURL:nil)
  }else{sendDetailsProfile()}
  detailsWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
 }
 func sendDetailsProfile(){guard let view=detailsWeb,let data=try? JSONSerialization.data(withJSONObject:detailsProfile()),let args=String(data:data,encoding:.utf8)else{return};detailsWindow?.title="\(config.name) · 宠物详情";view.evaluateJavaScript("window.loadProfile(\(args))"){_,error in if let error=error{if self.smoke{self.finishSmoke(error:error.localizedDescription)};return};if self.smoke && !self.detailsSmokeStarted{self.detailsSmokeStarted=true;self.runDetailsPageChecks()}}}
 func runDetailsPageChecks(){
  let menu=makeMenu();let tailMenu=menu.items.first{$0.title.hasPrefix("静坐时的尾巴")}?.submenu;let tailMenuOK=tailMenu?.items.count==3 && tailMenu?.items.contains{$0.representedObject as? String=="random" && $0.state == .on}==true;let menuOK=tailMenuOK && menu.items.contains{$0.action == #selector(showDetails(_:))} && menu.items.first{$0.title=="动作选择"}?.submenu?.items.count==actionIDs.count && menu.items.first{$0.title=="播放控制"}?.submenu?.items.count==3
  var results=smokeChecks["results"] as? [[String:Any]] ?? [];results.append(["control":"context menu exposes sitting, looking, yawning, grooming and playback controls","ok":menuOK]);smokeChecks["results"]=results
  results += floatingMenu.smokeChecks()
  results += teaserCursor.smokeChecks()
  results += cursorStyles.smokeChecks()
  results += runBasicChecks();smokeChecks["results"]=results
  let wasFocus=focusModeEnabled;setFocusMode(true,persist:false);updateFocusMenu();let focusAccess=focusMenuWindow?.isVisible==true && focusMenuWindow?.ignoresMouseEvents==false && window.ignoresMouseEvents
  let stableMenu=status.menu;menuWillOpen(stableMenu!);refreshMenu();let keptMenu=status.menu===stableMenu;menuDidClose(stableMenu!);setFocusMode(wasFocus,persist:false)
  results.append(["control":"focus mode keeps cat context-menu input and surrounding click-through","ok":focusAccess]);results.append(["control":"playback refresh does not replace an open menu","ok":keptMenu]);smokeChecks["results"]=results

  detailsWindow?.orderOut(nil)
  let blank=NSPoint(x:window.frame.minX+2,y:window.frame.maxY-2)
  NSCursor.arrow.set();let usedDefault=cursorStyles.applyDefault(at:blank)
  results.append(["control":"transparent cat canvas forces approved default cursor rather than cached system arrow","ok":usedDefault && NSCursor.current === PetCursorStyles.arrow])
  let cursorEnabled=mouseInteractionEnabled,cursorPaused=paused;mouseInteractionEnabled=true;paused=false
  let f=window.frame,near=NSPoint(x:f.minX+(config.mouseInteraction?.anchor[0] ?? 544)/(config.displayFrame?.width ?? 1024)*f.width,y:f.maxY-(258+(config.displayFrame?.paddingTop ?? 0))/(config.displayFrame?.height ?? 512)*f.height),far=NSPoint(x:f.maxX+500,y:f.maxY+500)
  results.append(["control":"petting hand uses interaction ellipse, including cat body, and ignores distant pointers","ok":isNearCat(near) && !isNearCat(far) && pettingCursorWindow != nil])
  bodyHit=true;bodyHitPoint=near;updatePettingCursor(near);let shown=pettingCursorWindow?.isVisible==true && pettingCursorActive
  beginMenuTracking();for _ in 0..<120{tick()};let keptSurface=pettingCursorWindow?.isVisible==true && pettingCursorActive;endMenuTracking()
  results.append(["control":"menu tracking never hides the originating cursor input window","ok":shown && keptSurface])
  updatePettingCursor(far);results.append(["control":"native cursor surface uses hand nearby and restores it on exit","ok":shown && pettingCursorWindow?.isVisible==false && !pettingCursorActive])
  paused=true;bodyHit=true;bodyHitPoint=near;updatePettingCursor(near);results.append(["control":"pause suppresses hand cursor","ok":pettingCursorWindow?.isVisible==false && !pettingCursorActive]);mouseInteractionEnabled=cursorEnabled;paused=cursorPaused;detailsWindow?.makeKeyAndOrderFront(nil)
  let originalState=state,originalAuto=automatic,originalDeadline=deadline;setState("natural_sit");automatic=false;deadline=Date().addingTimeInterval(-1);lastTick=Date().addingTimeInterval(-0.05);menuWillOpen(menu);let x=window.frame.minX;tick();let menuHolds=window.frame.minX==x && state=="natural_sit";menuDidClose(menu);automatic=originalAuto;deadline=originalDeadline;setState(originalState);results.append(["control":"open menu holds pet position and automatic state changes","ok":menuHolds && menuOpenedAt==nil])
  let original=config!;config=PetConfig(focusMode:original.focusMode,displayFrame:original.displayFrame,mouseInteraction:original.mouseInteraction,schemaVersion:original.schemaVersion,id:"custom-pet",name:"别的小伙伴",atlas:original.atlas,animations:original.animations,defaultState:original.defaultState,description:"自己的介绍",main:nil);let custom=detailsProfile();config=original
  results.append(["control":"custom pack profile uses its own identity and atlas portrait fallback","ok":custom["nickname"] as? String == "别的小伙伴" && custom["introduction"] as? String == "自己的介绍" && !(custom["portrait"] as? String ?? "").isEmpty]);let previousWindow=detailsWindow;detailsWindow?.close();let closed=detailsWindow?.isVisible==false;showDetails(nil);results.append(["control":"closing details preserves pet and reopening reuses its window","ok":closed && window.isVisible && detailsWindow===previousWindow && detailsWindow?.isVisible==true]);smokeChecks["results"]=results
  let script="""
  void(async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms)),results=[];await wait(120);results.push({control:'details page includes sitting, looking, yawning and grooming',ok:detailsDebug.ready&&detailsDebug.nickname==='夏天'&&detailsDebug.actions===5&&document.querySelectorAll('.feature').length===3});await document.querySelector('#portrait').decode();results.push({control:'details portrait loaded',ok:document.querySelector('#portrait').naturalWidth>0});document.querySelector('#pause').click();await wait(160);results.push({control:'details pauses natural sitting',ok:document.querySelector('#status').textContent.includes('已暂停')});document.querySelector('#play').click();await wait(160);results.push({control:'details resumes natural sitting',ok:document.querySelector('#status').textContent.includes('正在 · 自然静坐')});document.querySelector('#replay').click();await wait(160);results.push({control:'details replay retains natural sitting',ok:document.querySelector('#status').textContent.includes('自然静坐')});window.webkit.messageHandlers.details.postMessage({type:'smoke',ok:results.every(x=>x.ok),results});})().catch(e=>window.webkit.messageHandlers.details.postMessage({type:'smoke',ok:false,message:String(e),results:[]}));
  """
  detailsWeb?.evaluateJavaScript(script){_,error in if let error=error{self.finishSmoke(error:error.localizedDescription)}}
 }
 func runBasicChecks()->[[String:Any]]{
  var results:[[String:Any]]=[];let previousPaused=paused;paused=false
  basics.toggleVisible();let hidden=basics.userHidden && !window.isVisible && status.menu != nil && basics.defaults.bool(forKey:"petHidden");let reopened=applicationShouldHandleReopen(NSApp,hasVisibleWindows:false)
  results.append(["control":"reopening a hidden running app shows the existing cat","ok":reopened && !basics.userHidden && window.isVisible])
  results.append(["control":"hidden pet stays recoverable from status menu and visibility is saved","ok":hidden && window.isVisible])
  basics.toggleTop();let normal=window.level == .normal && pettingCursorWindow?.level == .normal && focusMenuWindow?.level == .normal && basics.defaults.bool(forKey:"alwaysOnTop")==false;basics.toggleTop();results.append(["control":"topmost switch updates native window levels and persists","ok":normal && window.level == .floating])
  basics.toggleLocked();focusReady=true;focusCooldownUntil = .distantPast;tickFocusMode(NSPoint(x:focusCatRect().midX,y:focusCatRect().midY),dt:300);let locked=focusRun==nil && basics.positionLocked;basics.toggleLocked();results.append(["control":"position lock prevents automatic focus travel","ok":locked && !basics.positionLocked])
  basics.locked();basics.displaySleep();basics.unlocked();let stillSleeping=basics.systemSuspended && !window.isVisible;basics.displayWake();results.append(["control":"lock and display sleep suspend independently and restore visible pet","ok":stillSleeping && !basics.systemSuspended && window.isVisible])
  let screens=[NSRect(x:-1440,y:100,width:1440,height:900),NSRect(x:0,y:0,width:1512,height:982)]
  let crossing=NSRect(x:-400,y:160,width:512,height:320);let selected=DesktopControls.screenFor(crossing,screens)!;let fit=DesktopControls.constrained(crossing,to:selected)
  let disconnected=DesktopControls.constrained(NSRect(x:-2000,y:300,width:512,height:320),to:screens[1]);let tiny=DesktopControls.constrained(NSRect(x:0,y:0,width:512,height:320),to:NSRect(x:0,y:0,width:320,height:240))
  results.append(["control":"screen boundaries use greatest overlap and recover disconnected or undersized displays","ok":selected==screens[0] && selected.contains(fit) && screens[1].contains(disconnected) && tiny.width==320 && tiny.height==240])
  let display=CGRect(x:1440,y:0,width:1512,height:982);results.append(["control":"fullscreen detection distinguishes current display from maximized or other-display windows","ok":DesktopControls.coversScreen(display,display) && !DesktopControls.coversScreen(CGRect(x:1440,y:24,width:1512,height:958),display) && !DesktopControls.coversScreen(CGRect(x:0,y:0,width:1512,height:982),display)])
  basics.heldKeys.removeAll();let oldPause=paused;basics.performShortcut(2);let firstPause=paused;basics.performShortcut(2);let repeatIgnored=paused==firstPause;basics.heldKeys.remove(2);basics.performShortcut(2);basics.heldKeys.removeAll();results.append(["control":"shortcut press toggles once, ignores repeat, and releases for next press","ok":firstPause != oldPause && repeatIgnored && paused==oldPause])
  basics.toggleVisible();summonFromMenuBar();results.append(["control":"status-bar summon reveals hidden cat without changing mode or pause","ok":!basics.userHidden && window.isVisible && statusSummonView?.hitTest(.zero)==nil && statusSummonView?.area != nil])
  statusSummonView?.arm();statusSummonView?.cancel();results.append(["control":"leaving status item cancels hover and click-through overlay preserves menu button","ok":statusSummonView?.hoverTimer==nil])
  let settings=basics.settingsMenu();results.append(["control":"settings expose visibility, position lock, layering, screens, fullscreen, login and shortcut profiles","ok":settings.items.contains{$0.title=="开机启动"} && settings.items.first{$0.title.hasPrefix("快捷键")}?.submenu?.items.count==3 && settings.items.first{$0.title=="移动到显示器"}?.submenu?.items.count==NSScreen.screens.count])
  let oldConfig=config!;let dir=smokeDir!.appendingPathComponent("invalid-pack");try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  if var object=(try? JSONSerialization.jsonObject(with:Data(contentsOf:packURL.appendingPathComponent("pet.json")))) as? [String:Any]{object["schemaVersion"]=99;if let data=try? JSONSerialization.data(withJSONObject:object){try? data.write(to:dir.appendingPathComponent("pet.json"))}}
  var rejected=false;do{try readPack(dir)}catch{rejected=true};results.append(["control":"invalid imported pack is rejected without replacing active cat","ok":rejected && config.id==oldConfig.id])
  basics.defaults.set(true,forKey:"positionLocked");basics.defaults.set("off",forKey:"shortcutProfile");basics.resetSettings();results.append(["control":"reset restores default mode, size, visibility and settings","ok":!basics.positionLocked && basics.alwaysOnTop && !basics.userHidden && basics.shortcutProfile=="controlOption" && !focusModeEnabled && window.frame.width==512])
  paused=previousPaused;basics.applyPause();return results
 }
 func finishDetailsSmoke(_ obj:[String:Any]){var results=smokeChecks["results"] as? [[String:Any]] ?? [];results+=obj["results"] as? [[String:Any]] ?? [];smokeChecks["results"]=results;smokeChecks["ok"]=results.allSatisfy{$0["ok"] as? Bool == true} && (obj["ok"] as? Bool == true);detailsWeb?.takeSnapshot(with:nil){image,_ in if let dir=self.smokeDir,let data=image?.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]){try? png.write(to:dir.appendingPathComponent("details-snapshot.png"))};self.finishSmoke(error:self.smokeChecks["ok"] as? Bool == true ? nil:(obj["message"] as? String ?? "Details interaction checks failed"))}}
 @objc func woke(){cancelFocusTravel();clearCursorInteraction();lastTick=Date();constrain()}
 @objc func quit(){restorePettingCursor();savePosition();NSApp.terminate(nil)}
 func reloadPetDocument(){
  cancelFocusTravel();restorePettingCursor();focusMenuWindow?.orderOut(nil);loaded=false;basics.lastHeartbeat=Date()
  guard let resource=Bundle.main.resourceURL,let html=try? String(contentsOf:resource.appendingPathComponent("pet.html")) else{basics.recoveryCount=3;showStaticFallback("动画页面无法读取，请重新安装程序。");return}
  web.loadHTMLString(html,baseURL:nil)
 }
 func recoverRenderer(_ reason:String){
  guard !smoke else{finishSmoke(error:reason);return};cancelFocusTravel();restorePettingCursor();focusMenuWindow?.orderOut(nil);loaded=false
  basics.recoveryCount+=1;basics.recoveryStarted=Date();basics.lastHeartbeat=Date()
  if basics.recoveryCount<=2,let resource=Bundle.main.resourceURL,(try? readPack(resource.appendingPathComponent("pet-pack"))) != nil{reloadPetDocument();return}
  showStaticFallback(reason)
 }
 func showStaticFallback(_ reason:String){
  guard let resource=Bundle.main.resourceURL,var image=try? Data(contentsOf:resource.appendingPathComponent("pet-pack/main.png")) else{let alert=NSAlert();alert.messageText="内置素材无法读取";alert.informativeText="请重新安装桌宠程序。";alert.runModal();NSApp.terminate(nil);return}
  if let data=try? Data(contentsOf:resource.appendingPathComponent("pet-pack/clips/natural_sit.webp")),let src=CGImageSourceCreateWithData(data as CFData,nil),let atlas=CGImageSourceCreateImageAtIndex(src,0,nil),let tile=atlas.cropping(to:CGRect(x:0,y:0,width:512,height:512)),let png=NSBitmapImageRep(cgImage:tile).representation(using:.png,properties:[:]){image=png}
  if window==nil{window=PetWindow(contentRect:NSRect(x:0,y:0,width:256,height:256),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false);window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=false;let view=PetView(frame:window.contentView!.bounds);view.setValue(false,forKey:"drawsBackground");view.autoresizingMask=[.width,.height];window.contentView=view;web=view;resetPosition();window.orderFrontRegardless();status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength);status.button?.image=NSImage(systemSymbolName:"pawprint.fill",accessibilityDescription:"Summer The Cat");let menu=NSMenu();add(menu,"退出",#selector(quit));status.menu=menu}
  let dw=config?.displayFrame?.width ?? 512,dh=config?.displayFrame?.height ?? 512,top=config?.displayFrame?.paddingTop ?? 0
  web.loadHTMLString("<html><body style='margin:0;background:transparent'><img style='position:absolute;left:\((dw-512)/2/dw*100)%;top:\(top/dh*100)%;width:\(512/dw*100)%;height:\(512/dh*100)%' src='data:image/png;base64,\(image.base64EncodedString())'></body></html>",baseURL:nil)
  let alert=NSAlert();alert.messageText="已切换为默认静坐画面";alert.informativeText=reason;alert.runModal()
 }
 func fail(_ text:String){if smoke{finishSmoke(error:text);return};if window==nil{showStaticFallback(text)}else{recoverRenderer(text)}}
 func finishSmoke(error:String?){guard !smokeFinished else{return};smokeFinished=true;guard let dir=smokeDir else{NSApp.terminate(nil);return}
  if let data=try? JSONSerialization.data(withJSONObject:smokeChecks,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:dir.appendingPathComponent("app-checks.json"))}
  if let error=error{try? error.write(to:dir.appendingPathComponent("app-error.txt"),atomically:true,encoding:.utf8);NSApp.terminate(nil);return}
  web.evaluateJavaScript("JSON.stringify(petDebug)"){value,error in
   try? (value as? String ?? "{}").write(to:dir.appendingPathComponent("app-smoke.json"),atomically:true,encoding:.utf8)
   self.web.takeSnapshot(with:nil){image,error in if let data=image?.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]){try? png.write(to:dir.appendingPathComponent("app-snapshot.png"))};NSApp.terminate(nil)}
  }
 }
}
@main struct SummerCatMain {
 static func main(){if CommandLine.arguments.contains("--diagnose-openai"){OpenAIDiagnostic.run();return};if !CommandLine.arguments.contains("--smoke-test"),!DesktopInstance.acquire(){return};let application=NSApplication.shared;let delegate=PetApp();application.delegate=delegate;withExtendedLifetime(delegate){application.run()}}
}
