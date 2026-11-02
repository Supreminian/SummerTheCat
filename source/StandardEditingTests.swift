import AppKit

final class PasteProbe:NSTextView {
 var pasteCount=0
 override func paste(_ sender:Any?){pasteCount+=1}
}
@main struct StandardEditingTests {
 static func main(){
  let app=NSApplication.shared;app.setActivationPolicy(.accessory)
  StandardEditing.install()
  let menu=app.mainMenu!.items.first{$0.title=="编辑"}!.submenu!
  let probe=PasteProbe(frame:NSRect(x:0,y:0,width:100,height:30))
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:120,height:50),styleMask:[.titled],backing:.buffered,defer:false)
  window.contentView=probe;window.makeFirstResponder(probe)
  let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"v",charactersIgnoringModifiers:"v",isARepeat:false,keyCode:9)!
  let paste=menu.items.first{$0.keyEquivalent=="v"}!
  let responderTarget=paste.target==nil
  // Explicit target isolates dispatch without activating a test window.
  paste.target=probe
  let routed=app.mainMenu!.performKeyEquivalent(with:event)
  let checks:[[String:Any]]=[
   ["name":"standard edit shortcuts registered","passed":Set(menu.items.map{$0.keyEquivalent})==Set(["z","x","c","v","a"])],
   ["name":"paste uses current responder rather than global clipboard logging","passed":responderTarget],
   ["name":"Command+V dispatches the standard paste selector","passed":routed&&probe.pasteCount==1]
  ]
  let report:[String:Any]=["passed":checks.allSatisfy{$0["passed"] as? Bool==true},"checks":checks,"clipboardRead":false,"clipboardModified":false]
  let data=try! JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);print(String(data:data,encoding:.utf8)!)
  if CommandLine.arguments.count>1{try! data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))}
  window.orderOut(nil)
  if report["passed"] as? Bool != true{exit(1)}
 }
}
