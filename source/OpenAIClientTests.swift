import Foundation

final class MockOpenAIProtocol:URLProtocol {
 static var code=200;static var contentType="text/event-stream";static var chunks:[Data]=[];static var captured:URLRequest?
 var stopped=false
 override class func canInit(with request:URLRequest)->Bool{true}
 override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
 override func startLoading(){
  Self.captured=request
  let response=HTTPURLResponse(url:request.url!,statusCode:Self.code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":Self.contentType])!
  client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
  let chunks=Self.chunks
  for (i,chunk) in chunks.enumerated(){DispatchQueue.global().asyncAfter(deadline:.now()+Double(i+1)*0.003){if !self.stopped{self.client?.urlProtocol(self,didLoad:chunk)}}}
  DispatchQueue.global().asyncAfter(deadline:.now()+Double(chunks.count+2)*0.003){if !self.stopped{self.client?.urlProtocolDidFinishLoading(self)}}
 }
 override func stopLoading(){stopped=true}
}

@main struct OpenAIClientTests {
 static var checks:[[String:Any]]=[]
 static func check(_ name:String,_ value:Bool){checks.append(["name":name,"passed":value]);if !value{fputs("FAIL: \(name)\n",stderr)}}
 static func event(_ value:[String:Any])->Data{let json=try! JSONSerialization.data(withJSONObject:value);return Data("data: ".utf8)+json+Data("\r\n\r\n".utf8)}
 static func run(code:Int=200,contentType:String="text/event-stream",chunks:[Data],cancel:Bool=false)->(Result<String,Error>?,[String]){
  MockOpenAIProtocol.code=code;MockOpenAIProtocol.contentType=contentType;MockOpenAIProtocol.chunks=chunks
  let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[MockOpenAIProtocol.self]
  var result:Result<String,Error>?;var deltas:[String]=[]
  let client=OpenAIStream(onDelta:{deltas.append($0)},onComplete:{result=$0})
  client.start(key:"test-placeholder-not-a-real-key",model:"gpt-6-luna",text:"你好",turns:[],configuration:config)
  if cancel{client.cancel()}
  let end=Date().addingTimeInterval(5)
  while result==nil && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
  return(result,deltas)
 }
 static func succeeded(_ result:Result<String,Error>?,_ expected:String)->Bool{if case .success(let value)=result{return value==expected};return false}
 static func failed(_ result:Result<String,Error>?,containing text:String)->Bool{if case .failure(let error)=result{return error.localizedDescription.contains(text)};return false}
 static func main(){
  let output="你好，夏天🐈";let packet=event(["type":"response.output_text.delta","delta":output])+event(["type":"response.completed","response":["status":"completed"]])
  var parser=OpenAISSEParser();var parsed:[[String:Any]]=[]
  for byte in packet{parsed+=parser.feed(Data([byte]))}
  check("SSE handles split Chinese/emoji UTF-8 and CRLF",parsed.count==2 && parsed.first?["delta"] as? String==output)
  let reply=run(chunks:[event(["type":"response.output_text.delta","delta":"你好，"]),event(["type":"response.output_text.delta","delta":"夏天🐈"]),event(["type":"response.completed"])])
  check("URLSession streams and returns complete text",succeeded(reply.0,output)&&reply.1.joined()==output)
  check("Request only targets official HTTPS endpoint",MockOpenAIProtocol.captured?.url==OpenAISettings.endpoint)
  check("Authorization remains native",MockOpenAIProtocol.captured?.value(forHTTPHeaderField:"Authorization")=="Bearer test-placeholder-not-a-real-key")
  check("401 has actionable message",failed(run(code:401,contentType:"application/json",chunks:[Data("{}".utf8)]).0,containing:"API Key"))
  check("quota and rate limits distinguished",failed(run(code:429,contentType:"application/json",chunks:[Data("{\"error\":{\"code\":\"insufficient_quota\"}}".utf8)]).0,containing:"额度不足"))
  check("EOF without completion is an error",failed(run(chunks:[event(["type":"response.output_text.delta","delta":"partial"])]).0,containing:"连接提前结束"))
  check("incomplete response is an error",failed(run(chunks:[event(["type":"response.incomplete"])]).0,containing:"未完成"))
  let server=run(chunks:[event(["type":"response.failed","response":["error":["code":"server_error","message":"The model failed to generate a response."]]])])
  check("response.failed preserves actual error code",failed(server.0,containing:"server_error"))
  let quota=run(chunks:[event(["type":"error","code":"insufficient_quota","message":"Quota exhausted."])])
  check("stream-level quota error is actionable",failed(quota.0,containing:"额度不足"))
  let redacted=OpenAIFailure.remote(["code":"invalid_api_key","message":"bad sk-test-secret-value"],secret:"sk-test-secret-value")
  check("diagnostics redact credentials",!redacted.message.contains("sk-test-secret-value"))
  check("non-streaming content rejected",failed(run(contentType:"application/json",chunks:[]).0,containing:"流式响应"))
  let cancelled=run(chunks:[event(["type":"response.output_text.delta","delta":"ignore"])] ,cancel:true)
  if case .failure(let error)=cancelled.0{check("cancel stops request",(error as? URLError)?.code == .cancelled)}else{check("cancel stops request",false)}
  let turns=(0..<20).map{ChatTurn(user:"user\($0)",assistant:"assistant\($0)")};let payload=OpenAIPayload.make(model:"gpt-6-luna",text:"new",turns:turns)
  let messages=payload["input"] as! [[String:String]]
  check("history contains bounded complete turns",messages.count==25&&messages.first?["content"]=="user8"&&messages.last?["content"]=="new")
  check("storage disabled and output bounded",payload["store"] as? Bool==false&&payload["max_output_tokens"] as? Int==2048)
  check("model ID validated",OpenAISettings.validModel("gpt-6-luna") && !OpenAISettings.validModel("bad\nmodel"))
  let service="summer-openai-test-"+UUID().uuidString
  do{try OpenAIKeychain.save("test-placeholder-not-a-real-key",service:service);check("Keychain roundtrip",try OpenAIKeychain.read(service:service)=="test-placeholder-not-a-real-key");try OpenAIKeychain.delete(service:service);check("Keychain removal",try OpenAIKeychain.read(service:service)==nil)}catch{check("Keychain roundtrip",false)}
  let report:[String:Any]=["passed":checks.allSatisfy{$0["passed"] as? Bool==true},"checks":checks,"liveAPIRequest":false]
  let data=try! JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
  if CommandLine.arguments.count>1{try! data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))}
  print(String(data:data,encoding:.utf8)!);if report["passed"] as? Bool != true{exit(1)}
 }
}
