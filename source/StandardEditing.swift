import AppKit

enum StandardEditing {
 static func install(){
  let main=NSMenu()
  let app=NSMenuItem();let applicationMenu=NSMenu();applicationMenu.addItem(withTitle:"退出夏天 AI",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");app.submenu=applicationMenu;main.addItem(app)
  let edit=NSMenuItem(title:"编辑",action:nil,keyEquivalent:"");let menu=NSMenu(title:"编辑")
  let commands:[(String,Selector,String,NSEvent.ModifierFlags)]=[
   ("撤销",Selector(("undo:")),"z",.command),("重做",Selector(("redo:")),"z",[.command,.shift]),
   ("剪切",#selector(NSText.cut(_:)),"x",.command),("复制",#selector(NSText.copy(_:)),"c",.command),
   ("粘贴",#selector(NSText.paste(_:)),"v",.command),("全选",#selector(NSText.selectAll(_:)),"a",.command)]
  for (title,action,key,modifiers) in commands{let item=NSMenuItem(title:title,action:action,keyEquivalent:key);item.keyEquivalentModifierMask=modifiers;item.target=nil;menu.addItem(item)}
  edit.submenu=menu;main.addItem(edit);NSApp.mainMenu=main
 }
}
