import AppKit
import WebKit

final class ConversationPanel:NSPanel {
 override var canBecomeKey:Bool {true}
 override var canBecomeMain:Bool {false}
}
final class ConversationWeb:WKWebView {
 override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
}

final class ConversationUI:NSObject,WKScriptMessageHandler,WKNavigationDelegate {
 weak var owner:PetApp?
 var panel:ConversationPanel?;var web:ConversationWeb?
 var visible=false;var motionActive=false;var phase="idle";var ready=false
 var previousApp:NSRunningApplication?
 lazy var aiSettings=OpenAISettingsUI(conversation:self)
 var stream:ChatStreaming?;var requestID:UUID?;var turns:[ChatTurn]=[];var lastPrompt:String?;var retryAllowed=false
 var apiState="unconfigured"
 func publishConfiguration(){
  let provider=AIProvider.current;let hasKey=(try? provider.readKey()) != nil
  send(["type":"configuration","provider":provider.name,"model":provider.model,"configured":hasKey])
 }
 func startRequest(_ text:String){
  guard requestID==nil else{return}
  lastPrompt=text;retryAllowed=false
  do{
   let provider=AIProvider.current
   guard let key=try provider.readKey(),!key.isEmpty else{throw OpenAIFailure("请先点击连接设置，填写 \(provider.name) API Key。")}
   let model=provider.model;guard provider.validModel(model) else{throw OpenAIFailure("请在连接设置中填写有效的模型 ID。")}
   let id=UUID();requestID=id;apiState="thinking"
   owner?.web.evaluateJavaScript("window.beginConversation?.()")
   send(["type":"response-start"])
   let request=provider.makeStream(onDelta:{[weak self] delta in
    guard let self=self,self.requestID==id else{return}
    self.apiState="streaming";self.send(["type":"response-delta","text":delta])
   },onComplete:{[weak self] result in
    guard let self=self,self.requestID==id else{return}
    self.requestID=nil;self.stream=nil;self.apiState="ready"
    switch result {
    case .success(let answer):
     self.turns.append(ChatTurn(user:text,assistant:answer));if self.turns.count>12{self.turns.removeFirst(self.turns.count-12)}
     self.retryAllowed=false;self.send(["type":"response-done","text":answer])
    case .failure(let error):
     self.retryAllowed=true;self.send(["type":"response-error","text":error.localizedDescription,"retry":true])
    }
    self.owner?.web.evaluateJavaScript("window.finishConversation?.()")
   })
   stream=request;request.start(key:key,model:model,text:text,turns:turns)
  }catch{
   apiState="error";retryAllowed=true
   send(["type":"response-error","text":error.localizedDescription,"retry":true])
   owner?.web.evaluateJavaScript("window.finishConversation?.()")
  }
 }
 func cancelRequest(){
  let wasRunning=requestID != nil;requestID=nil;let previous=stream;stream=nil;previous?.cancel()
  if wasRunning{retryAllowed=true;send(["type":"response-error","text":"已停止回复，可以重新发送或重试。","retry":true])}
  apiState="ready";owner?.web.evaluateJavaScript("window.finishConversation?.()")
 }
 func clearConversation(){
  cancelRequest();turns=[];lastPrompt=nil;retryAllowed=false;send(["type":"clear"]);publishConfiguration()
 }
 init(owner:PetApp){self.owner=owner;super.init()}
 func create(){
  guard panel==nil,let owner=owner,let resource=Bundle.main.resourceURL else{return}
  let p=ConversationPanel(contentRect:NSRect(x:0,y:0,width:356,height:414),styleMask:[.borderless],backing:.buffered,defer:false)
  p.title="和夏天聊聊 · AI";p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false
  p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
  let configuration=WKWebViewConfiguration();configuration.userContentController.add(self,name:"chat")
  let view=ConversationWeb(frame:p.contentView!.bounds,configuration:configuration)
  view.navigationDelegate=self;view.setValue(false,forKey:"drawsBackground");view.autoresizingMask=[.width,.height]
  p.contentView=view;panel=p;web=view
  owner.window.addChildWindow(p,ordered:.above)
  if let html=try? String(contentsOf:resource.appendingPathComponent("chat.html"),encoding:.utf8){view.loadHTMLString(html,baseURL:nil)}
 }
 func show(){
  guard let owner=owner,owner.loaded else{return}
  if !visible{previousApp=NSWorkspace.shared.frontmostApplication}
  create();visible=true;owner.restorePettingCursor(restoreFocus:false)
  owner.basics.showFromAnotherInstance();updatePosition()
  panel?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
  owner.web.evaluateJavaScript("window.beginConversation?.()")
  if ready{send(["type":"open"])}
  owner.refreshMenu()
 }
 func hide(){
  visible=false;panel?.orderOut(nil);cancelRequest()
  owner?.refreshMenu()
  if let previous=previousApp,previous.processIdentifier != ProcessInfo.processInfo.processIdentifier,!previous.isTerminated{previous.activate(options:[.activateIgnoringOtherApps])}
 }
 func updatePosition(){
  guard visible,let owner=owner,let panel=panel else{return}
  guard owner.window.isVisible,!owner.basics.systemSuspended,!owner.basics.userHidden,!owner.basics.fullscreenHidden else{panel.orderOut(nil);return}
  let cat=owner.focusCatRect();let screen=(NSScreen.screens.first{$0.visibleFrame.contains(NSPoint(x:cat.midX,y:cat.midY))} ?? owner.window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
  let width=min(356,screen.width-20),height=min(414,screen.height-20)
  var x=cat.maxX-14;var side="right"
  if x+width>screen.maxX-8{x=cat.minX-width+14;side="left"}
  x=max(screen.minX+8,min(x,screen.maxX-width-8))
  let y=max(screen.minY+8,min(cat.maxY-22,screen.maxY-height-8))
  let rect=NSRect(x:x,y:y,width:width,height:height)
  if panel.frame != rect{panel.setFrame(rect,display:true);send(["type":"layout","side":side])}
  panel.level=owner.basics.alwaysOnTop ? NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+2):.normal
  if !panel.isVisible{panel.orderFrontRegardless()}
 }
 func send(_ value:[String:Any]){
  guard ready,let data=try? JSONSerialization.data(withJSONObject:value),let json=String(data:data,encoding:.utf8) else{return}
  web?.evaluateJavaScript("window.chatReceive(\(json))")
 }
 func updateMotion(_ value:[String:Any]){
  motionActive=value["active"] as? Bool ?? false;phase=value["phase"] as? String ?? "idle"
  send(["type":"status","phase":phase])
  owner?.refreshMenu()
 }
 func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){
  guard message.webView===web,let value=message.body as? [String:Any],let type=value["type"] as? String else{return}
  switch type {
  case "ready":ready=true;publishConfiguration();send(["type":"status","phase":phase]);if visible{send(["type":"open"]);updatePosition()}
  case "settings":aiSettings.show()
  case "cancel":cancelRequest()
  case "clear":clearConversation()
  case "retry":if retryAllowed,let prompt=lastPrompt{startRequest(prompt)}
  case "begin":if visible,requestID==nil{owner?.web.evaluateJavaScript("window.beginConversation?.()")}
  case "submit":
   guard requestID==nil,let text=value["text"] as? String,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.count<=1000 else{return}
   startRequest(text)
  case "close":hide()
  default:break
  }
 }
 func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel:.allow)}
}

extension PetApp {
 @objc func showConversation(_ sender:Any?){conversation.show()}
 @objc func showAISettings(_ sender:Any?){conversation.aiSettings.show()}
}
