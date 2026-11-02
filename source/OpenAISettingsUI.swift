import AppKit

final class OpenAISettingsUI:NSObject,NSWindowDelegate {
 weak var conversation:ConversationUI?
 var providerField:NSPopUpButton!
 var selectedProvider:AIProvider{AIProvider.allCases[max(0,providerField.indexOfSelectedItem)]}
 var window:NSWindow?;var keyField:NSSecureTextField!;var modelField:NSComboBox!;var statusLabel:NSTextField!
 var testTask:ChatStreaming?;var testID:UUID?
 init(conversation:ConversationUI){self.conversation=conversation;super.init()}
 func show(){
  if window==nil{create()}
  providerField.selectItem(at:AIProvider.allCases.firstIndex(of:AIProvider.current)!);loadProvider();window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
 }
 func create(){
  let w=NSWindow(contentRect:NSRect(x:0,y:0,width:468,height:530),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  w.title="AI 连接设置 · Gemini / OpenAI";w.isReleasedWhenClosed=false;w.delegate=self;w.level = .floating;w.center()
  w.contentView=PetMenuSurface(frame:w.contentView!.bounds)
  let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=11;root.translatesAutoresizingMaskIntoConstraints=false
  let title=NSTextField(labelWithString:"让夏天认真回答你");title.font = .systemFont(ofSize:20,weight:.semibold)
  let hint=NSTextField(wrappingLabelWithString:"选择模型服务，填写对应 API Key。不同服务的密钥分开保存在此 Mac 的钥匙串中。")
  hint.font = .systemFont(ofSize:12);hint.textColor = .secondaryLabelColor
  root.addArrangedSubview(title);root.addArrangedSubview(hint)
  root.addArrangedSubview(NSTextField(labelWithString:"服务商"))
  providerField=NSPopUpButton();providerField.addItems(withTitles:AIProvider.allCases.map{$0.name});providerField.target=self;providerField.action=#selector(providerChanged);providerField.setAccessibilityLabel("AI 服务商")
  let providerRow=NSStackView();providerRow.orientation = .horizontal;providerRow.spacing=12;providerRow.addArrangedSubview(providerField)
  let getKey=PetClickButton(title:"获取密钥 ↗",target:self,action:#selector(openKeyPage));getKey.bezelStyle = .rounded;providerRow.addArrangedSubview(getKey);root.addArrangedSubview(providerRow)
  root.addArrangedSubview(NSTextField(labelWithString:"API Key"))
  keyField=NSSecureTextField();keyField.placeholderString="输入 API Key";keyField.setAccessibilityLabel("AI API Key")
  let keyRow=NSStackView();keyRow.orientation = .horizontal;keyRow.spacing=8
  keyRow.addArrangedSubview(keyField)
  let paste=PetClickButton(title:"粘贴密钥",target:self,action:#selector(pasteKey));paste.bezelStyle = .rounded;paste.setContentHuggingPriority(.required,for:.horizontal);keyRow.addArrangedSubview(paste);root.addArrangedSubview(keyRow)
  root.addArrangedSubview(NSTextField(labelWithString:"模型"))
  modelField=NSComboBox();modelField.addItems(withObjectValues:["gpt-6-luna","gpt-6.1-sol","gpt-6-astra","gpt-4.1-mini"]);modelField.isEditable=true;modelField.setAccessibilityLabel("AI 模型");root.addArrangedSubview(modelField)
  statusLabel=NSTextField(wrappingLabelWithString:"");statusLabel.font = .systemFont(ofSize:11);statusLabel.textColor = .secondaryLabelColor;root.addArrangedSubview(statusLabel)
  let row=NSStackView();row.orientation = .horizontal;row.spacing=10
  for (name,action) in [("移除密钥",#selector(removeKey)),("验证对话",#selector(testConnection)),("保存",#selector(save))]{let button=PetClickButton(title:name,target:self,action:action);button.bezelStyle = .rounded;if name=="保存"{button.keyEquivalent="\r"};row.addArrangedSubview(button)}
  root.addArrangedSubview(row)
  let note=NSTextField(wrappingLabelWithString:"验证对话会发送简短测试消息。Gemini 免费层仍受模型、地区和项目限额约束；是否免费由所选项目决定。")
  note.font = .systemFont(ofSize:10);note.textColor = .tertiaryLabelColor;root.addArrangedSubview(note)
  w.contentView!.addSubview(root)
  NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:w.contentView!.leadingAnchor,constant:24),root.trailingAnchor.constraint(equalTo:w.contentView!.trailingAnchor,constant:-24),root.topAnchor.constraint(equalTo:w.contentView!.topAnchor,constant:22),keyRow.widthAnchor.constraint(equalTo:root.widthAnchor),keyField.widthAnchor.constraint(greaterThanOrEqualToConstant:200),modelField.widthAnchor.constraint(equalTo:root.widthAnchor),statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant:78)])
  window=w
 }
 func refreshSavedStatus(){
  do{let exists=try selectedProvider.readKey() != nil;keyField.placeholderString=exists ? "已保存密钥；留空表示保持不变":"输入 API Key";statusLabel.stringValue=exists ? "已保存 API Key。可验证连接或更换模型。":"尚未配置密钥。填写后点击保存。"}catch{statusLabel.stringValue=error.localizedDescription}
 }
 @objc func pasteKey(){
  // Read only after an explicit click, directly into a masked native field.
  guard let value=NSPasteboard.general.string(forType:.string),!value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{statusLabel.stringValue="剪贴板里没有文本，请先复制 API Key。";return}
  keyField.stringValue=value.trimmingCharacters(in:.whitespacesAndNewlines)
  window?.makeFirstResponder(keyField);statusLabel.stringValue="已粘贴密钥。可以验证连接并保存。"
 }
 func values()throws->(String,String){
  let model=modelField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
  guard selectedProvider.validModel(model) else{throw OpenAIFailure("请填写所选服务的有效模型 ID，例如 \(selectedProvider.defaultModel)。")}
  let newKey=keyField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
  let key=try newKey.isEmpty ? selectedProvider.readKey() ?? "":newKey
  guard key.count>=12,!key.contains(where:{$0.isWhitespace}) else{throw OpenAIFailure("请填写有效的 API Key。")}
  return (key,model)
 }
 @objc func providerChanged(){loadProvider()}
 func loadProvider(){
  testID=nil;testTask?.cancel();testTask=nil;keyField.stringValue=""
  modelField.removeAllItems();modelField.addItems(withObjectValues:selectedProvider.models);modelField.stringValue=selectedProvider.model
  refreshSavedStatus();window?.makeFirstResponder(keyField)
 }
 @objc func openKeyPage(){
  let url=selectedProvider == .gemini ? "https://aistudio.google.com/app/apikey":"https://platform.openai.com/api-keys"
  NSWorkspace.shared.open(URL(string:url)!)
 }
 @objc func save(){
  do{
   let (key,model)=try values();let provider=selectedProvider
   let changed=provider != AIProvider.current || model != AIProvider.current.model
   let newKey = !keyField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
   if newKey{try OpenAIKeychain.save(key,service:provider.keychainService)}
   provider.setModel(model);AIProvider.current=provider;keyField.stringValue="";refreshSavedStatus()
   if changed{conversation?.clearConversation()}else if newKey{conversation?.cancelRequest()}
   statusLabel.stringValue="已保存 \(provider.name) 设置。回到对话框即可聊天。";conversation?.publishConfiguration()
  }catch{statusLabel.stringValue=error.localizedDescription}
 }
 @objc func removeKey(){
  do{testID=nil;testTask?.cancel();testTask=nil;try OpenAIKeychain.delete(service:selectedProvider.keychainService);keyField.stringValue="";if selectedProvider==AIProvider.current{conversation?.cancelRequest()};refreshSavedStatus();conversation?.publishConfiguration()}catch{statusLabel.stringValue=error.localizedDescription}
 }
 @objc func testConnection(){
  do{
   let (key,model)=try values();testTask?.cancel();let id=UUID();testID=id
   statusLabel.stringValue="正在发送短消息，验证实际对话能力…"
   let request=selectedProvider.makeStream(onDelta:{_ in},onComplete:{[weak self] result in
    guard let self=self,self.testID==id else{return}
    self.testTask=nil;self.testID=nil
    switch result {
    case .success:self.statusLabel.stringValue="对话验证成功：已收到模型回复。新设置请点击保存。"
    case .failure(let error):self.statusLabel.stringValue=error.localizedDescription
    }
   })
   testTask=request;request.start(key:key,model:model,text:"请只回复：连接正常。",turns:[])
  }catch{statusLabel.stringValue=error.localizedDescription}
 }
 func windowWillClose(_ notification:Notification){testID=nil;testTask?.cancel();testTask=nil;keyField.stringValue="";conversation?.publishConfiguration()}
}
