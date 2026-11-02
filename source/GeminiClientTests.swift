import Foundation

final class MockGeminiProtocol:URLProtocol {
 static var code=200;static var chunks:[Data]=[];static var captured:URLRequest?
 var stopped=false
 override class func canInit(with request:URLRequest)->Bool{true}
 override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
 override func startLoading(){
  Self.captured=request;let chunks=Self.chunks
  client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:Self.code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":Self.code==200 ? "text/event-stream":"application/json"])!,cacheStoragePolicy:.notAllowed)
  for (i,chunk) in chunks.enumerated(){DispatchQueue.global().asyncAfter(deadline:.now()+Double(i+1)*0.003){if !self.stopped{self.client?.urlProtocol(self,didLoad:chunk)}}}
  DispatchQueue.global().asyncAfter(deadline:.now()+Double(chunks.count+2)*0.003){if !self.stopped{self.client?.urlProtocolDidFinishLoading(self)}}
 }
 override func stopLoading(){stopped=true}
}
@main struct GeminiClientTests {
 static var checks:[[String:Any]]=[]
 static func check(_ name:String,_ passed:Bool){checks.append(["name":name,"passed":passed])}
 static func event(_ value:[String:Any])->Data{Data("data: ".utf8)+(try! JSONSerialization.data(withJSONObject:value))+Data("\n\n".utf8)}
 static func chunk(_ text:String,finish:String?=nil,thought:Bool=false)->[String:Any]{
  var c:[String:Any]=["content":["role":"model","parts":[["text":text,"thought":thought]]]];if let finish=finish{c["finishReason"]=finish};return ["candidates":[c]]
 }
 static func run(provider:AIProvider = .gemini,code:Int=200,chunks:[Data],cancel:Bool=false)->(Result<String,Error>?,String){
  MockGeminiProtocol.code=code;MockGeminiProtocol.chunks=chunks
  let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockGeminiProtocol.self]
  var result:Result<String,Error>?;var output=""
  let client=provider.makeStream(onDelta:{output+=$0},onComplete:{result=$0})
  client.start(key:"test-gemini-placeholder-not-a-real-key",model:provider.defaultModel,text:"你好",turns:[ChatTurn(user:"我是阿明",assistant:"你好，阿明")],configuration:config)
  if cancel{client.cancel()}
  let end=Date().addingTimeInterval(5);while result==nil && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
  return(result,output)
 }
 static func success(_ result:Result<String,Error>?,_ text:String)->Bool{if case .success(let value)=result{return value==text};return false}
 static func failure(_ result:Result<String,Error>?,contains text:String)->Bool{if case .failure(let error)=result{return error.localizedDescription.contains(text)};return false}
 static func main(){
  let result=run(chunks:[event(chunk("思考内容",thought:true)),event(chunk("你好，")),event(chunk("阿明🐈",finish:"STOP"))])
  check("native Gemini SSE and Unicode",success(result.0,"你好，阿明🐈")&&result.1=="你好，阿明🐈")
  let request=MockGeminiProtocol.captured!
  check("official endpoint without key in URL",request.url?.host=="generativelanguage.googleapis.com"&&request.url?.query=="alt=sse")
  check("provider-specific authentication",request.value(forHTTPHeaderField:"x-goog-api-key")=="test-gemini-placeholder-not-a-real-key"&&request.value(forHTTPHeaderField:"Authorization")==nil)
  let body=GeminiPayload.make(text:"你好",turns:[ChatTurn(user:"我是阿明",assistant:"你好，阿明")]);let contents=body["contents"] as! [[String:Any]]
  check("native user/model history and system instruction",contents.compactMap{$0["role"] as? String}==["user","model","user"]&&body["systemInstruction"] != nil&&body["input"]==nil)
  check("no provider credential crossover",AIProvider.gemini.keychainService != AIProvider.openai.keychainService)
  check("Gemini model ID cannot change host or path",GeminiPayload.endpoint(model:"../../api?key=bad")==nil)
  check("Gemini credentials redacted",!GeminiErrors.make(status:400,body:["error":["message":"invalid AIza-test-private"]],model:"gemini-test",secret:"AIza-test-private").message.contains("AIza-test-private"))
  let quota=Data("{\"error\":{\"code\":429,\"status\":\"RESOURCE_EXHAUSTED\",\"message\":\"Quota exceeded\"}}".utf8)
  check("free quota errors actionable",failure(run(code:429,chunks:[quota]).0,contains:"RESOURCE_EXHAUSTED"))
  check("safety block handled",failure(run(chunks:[event(["promptFeedback":["blockReason":"SAFETY"]])]).0,contains:"SAFETY"))
  check("truncated output not treated as complete",failure(run(chunks:[event(chunk("partial",finish:"MAX_TOKENS"))]).0,contains:"长度上限"))
  check("missing final reason rejected",failure(run(chunks:[event(chunk("partial"))]).0,contains:"STREAM_INTERRUPTED"))
  let openAI=run(provider:.openai,chunks:[event(["type":"response.output_text.delta","delta":"原有接口正常"]),event(["type":"response.completed"])])
  check("OpenAI factory remains functional",success(openAI.0,"原有接口正常")&&MockGeminiProtocol.captured?.url?.host=="api.openai.com"&&MockGeminiProtocol.captured?.value(forHTTPHeaderField:"x-goog-api-key")==nil)
  let cancellation=run(chunks:[event(chunk("ignore",finish:"STOP"))],cancel:true)
  if case .failure(let error)=cancellation.0{check("cancel stops Gemini stream",(error as? URLError)?.code == .cancelled)}else{check("cancel stops Gemini stream",false)}
  let report:[String:Any]=["passed":checks.allSatisfy{$0["passed"] as? Bool==true},"liveAPIRequest":false,"checks":checks]
  let data=try! JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);print(String(data:data,encoding:.utf8)!)
  if CommandLine.arguments.count>1{try! data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))}
  if report["passed"] as? Bool != true{exit(1)}
 }
}
