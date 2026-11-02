import AppKit
import WebKit

extension PetApp {
 func runConversationSmoke(){
  web.evaluateJavaScript("setState('groom',true);playback.seek(40);playback.markPresented();"){_,_ in self.showConversation(nil);self.waitForConversationSmoke(0)}
 }
 func waitForConversationSmoke(_ attempt:Int){
  guard conversation.ready else{
   if attempt>40{finishSmoke(error:"Conversation did not become ready");return}
   DispatchQueue.main.asyncAfter(deadline:.now()+0.25){self.waitForConversationSmoke(attempt+1)};return
  }
  let script="""
  void(async()=>{
   const wait=ms=>new Promise(r=>setTimeout(r,ms)),results=[];
   results.push({control:'opening native conversation queues entry after the existing groom',ok:playback.state==='groom'&&playback.pendingState==='thinking_enter'});
   for(let n=0;n<400&&playback.state!=='thinking_loop';n++)await wait(40);
   results.push({control:'native app reaches the supplied thinking loop',ok:playback.state==='thinking_loop'&&chatMotion.phase==='listening'});
   notify({type:'conversation-snapshot'});
   await wait(250);window.finishConversation();
   results.push({control:'finish queues return without cutting the loop',ok:playback.state==='thinking_loop'&&playback.pendingState==='thinking_exit'});
   for(let n=0;n<350&&chatMotion.active;n++)await wait(40);
   results.push({control:'returns to sitting and releases conversation',ok:playback.isIdle()&&!chatMotion.active});
   notify({type:'conversation-smoke',ok:results.every(r=>r.ok),results});
  })().catch(e=>notify({type:'conversation-smoke',ok:false,message:String(e)}));
  """
  web.evaluateJavaScript(script){_,error in if let error=error{self.finishSmoke(error:error.localizedDescription)}}
 }
 func captureConversationSmoke(){
  guard let dir=smokeDir else{return}
  web.takeSnapshot(with:nil){image,_ in self.writeConversationImage(image,to:dir.appendingPathComponent("cat.png"))}
  conversation.web?.takeSnapshot(with:nil){image,_ in self.writeConversationImage(image,to:dir.appendingPathComponent("chat.png"))}
  if CommandLine.arguments.contains("--settings-smoke"){
   conversation.aiSettings.show()
   DispatchQueue.main.asyncAfter(deadline:.now()+0.15){
    let ui=self.conversation.aiSettings;guard let view=ui.window?.contentView else{return}
    view.layoutSubtreeIfNeeded()
    let modelRect=ui.modelField.convert(ui.modelField.bounds,to:view),keyRect=ui.keyField.convert(ui.keyField.bounds,to:view)
    let report:[String:Any]=["passed":ui.selectedProvider == .gemini && ui.modelField.stringValue==AIProvider.gemini.defaultModel && view.bounds.contains(modelRect) && view.bounds.contains(keyRect),"providerOptions":ui.providerField.itemTitles,"defaultModel":ui.modelField.stringValue,"secretFieldEmpty":ui.keyField.stringValue.isEmpty,"liveAPIRequest":false]
    if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:dir.appendingPathComponent("settings-checks.json"))}
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);if let data=bitmap.representation(using:.png,properties:[:]){try? data.write(to:dir.appendingPathComponent("settings.png"))}}
   }
  }
 }
 func writeConversationImage(_ image:NSImage?,to url:URL){
  if let tiff=image?.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]){try? png.write(to:url)}
 }
 func finishConversationSmoke(_ value:[String:Any]){
  let cat=focusCatRect(),panel=conversation.panel?.frame ?? .zero
  let screen=conversation.panel?.screen?.visibleFrame ?? .zero
  var result=value;result["nativePanel"]=["keyWindow":conversation.panel?.isKeyWindow ?? false,"canBecomeKey":conversation.panel?.canBecomeKey ?? false,"insideScreen":screen.contains(panel),"rightOfHead":panel.midX>cat.midX,"x":panel.minX,"y":panel.minY,"width":panel.width,"height":panel.height]
  if let dir=smokeDir,let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:dir.appendingPathComponent("conversation-checks.json"))}
  smokeChecks["conversation"]=result;finishSmoke(error:value["ok"] as? Bool == true ? nil:"Conversation integration failed")
 }
}
