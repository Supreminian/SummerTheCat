import Foundation

// Explicit diagnostic mode uses only this application's own Keychain item.
// It never prints credentials, headers, conversation history, or response text.
enum OpenAIDiagnostic {
 static func run(){
  var report:[String:Any]=["liveAPIRequest":false,"model":OpenAISettings.model]
  do{
   guard let key=try OpenAIKeychain.read(allowInteraction:false) else{report["error"]="此应用未保存 API Key";write(report);return}
   var model=OpenAISettings.model
   if let i=CommandLine.arguments.firstIndex(of:"--model"),CommandLine.arguments.count>i+1{model=CommandLine.arguments[i+1]}
   guard OpenAISettings.validModel(model) else{report["error"]="模型 ID 无效";write(report);return}
   report["model"]=model;report["liveAPIRequest"]=true;var done=false
   let client=OpenAIStream(onDelta:{_ in},onComplete:{result in
    switch result{
    case .success(let text):report["ok"]=true;report["outputCharacters"]=text.count
    case .failure(let error):
     report["ok"]=false
     if let failure=error as? OpenAIFailure{report["error"]=failure.message;report["code"]=failure.code;report["requestID"]=failure.requestID}
     else{report["error"]="请求失败"}
    };done=true
   })
   client.start(key:key,model:model,text:"请只回复：连接正常。",turns:[])
   let deadline=Date().addingTimeInterval(125)
   while !done && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.05))}
   if !done{client.cancel();report["ok"]=false;report["error"]="诊断请求超时"}
   write(report)
  }catch{report["ok"]=false;report["error"]="无法无交互地读取本应用钥匙串项目，请在应用内使用验证对话。";write(report)}
 }
 static func write(_ report:[String:Any]){
  let data=try! JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);print(String(data:data,encoding:.utf8)!)
  if let i=CommandLine.arguments.firstIndex(of:"--report"),CommandLine.arguments.count>i+1{try? data.write(to:URL(fileURLWithPath:CommandLine.arguments[i+1]))}
 }
}
