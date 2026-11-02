import Foundation

enum GeminiPayload {
 static func endpoint(model:String)->URL?{
  guard model.range(of:"^gemini-[A-Za-z0-9._-]{1,100}$",options:.regularExpression) != nil else{return nil}
  return URL(string:"https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")
 }
 static func make(text:String,turns:[ChatTurn])->[String:Any]{
  // Share the bounded turn policy; translate roles into the native Gemini schema.
  let input=OpenAIPayload.make(model:"unused",text:text,turns:turns)["input"] as! [[String:String]]
  let contents=input.map{item->[String:Any] in ["role":item["role"]=="assistant" ? "model":"user","parts":[["text":item["content"]!]]]}
  return ["contents":contents,"systemInstruction":["parts":[["text":OpenAIPayload.instructions]]],"generationConfig":["maxOutputTokens":2048]]
 }
}
enum GeminiErrors {
 static func make(status:Int,body:[String:Any],model:String,requestID:String="",secret:String="")->OpenAIFailure{
  let error=body["error"] as? [String:Any] ?? body
  let code=error["status"] as? String ?? "HTTP_\(status)"
  var detail=error["message"] as? String ?? "服务没有提供详细说明。"
  if !secret.isEmpty{detail=detail.replacingOccurrences(of:secret,with:"[已隐藏密钥]")}
  detail=detail.replacingOccurrences(of:"AIza[A-Za-z0-9_-]+",with:"[已隐藏密钥]",options:.regularExpression)
  detail=String(detail.prefix(450))
  let reasons=(error["details"] as? [[String:Any]] ?? []).compactMap{$0["reason"] as? String}
  let summary:String
  if reasons.contains("API_KEY_INVALID"){summary="Gemini API Key 无效，请在 AI 连接设置中更新。"}
  else if status==429||code=="RESOURCE_EXHAUSTED"{summary="Gemini 免费额度或请求速率已达上限，请检查 AI Studio 限额并稍后重试。"}
  else if detail.lowercased().contains("location")||detail.lowercased().contains("region"){summary="当前地区或项目配置无法使用此 Gemini API，请检查服务支持范围。"}
  else if status==401||status==403{summary="Gemini 密钥或项目权限不足，请检查密钥限制和 API 是否启用。"}
  else if status==404{summary="Gemini 模型不可用，请在 AI 连接设置中更换模型。"}
  else if status>=500{summary="Google Gemini 服务暂时不可用，请稍后重试。"}
  else{summary="Gemini 请求未完成，具体原因如下。"}
  var message=summary+"\n错误码："+code+"\n"+detail+"\n模型："+model
  if !requestID.isEmpty{message+="\n请求编号："+requestID}
  return OpenAIFailure(message,code:code,model:model,requestID:requestID)
 }
}

final class GeminiStream:NSObject,URLSessionDataDelegate,ChatStreaming {
 let onDelta:(String)->Void;let onComplete:(Result<String,Error>)->Void
 private var session:URLSession?;private var task:URLSessionDataTask?
 private let lock=NSLock();private var finished=false
 private var parser=OpenAISSEParser();private var output="";private var status=0;private var errorBody=Data();private var finishReason:String?
 private var modelID="";private var secret="";private var requestID=""
 init(onDelta:@escaping(String)->Void,onComplete:@escaping(Result<String,Error>)->Void){self.onDelta=onDelta;self.onComplete=onComplete}
 func start(key:String,model:String,text:String,turns:[ChatTurn],configuration:URLSessionConfiguration = .ephemeral){
  guard let url=GeminiPayload.endpoint(model:model) else{finish(.failure(OpenAIFailure("Gemini 模型 ID 无效，请在 AI 连接设置中修改。")));return}
  modelID=model;secret=key
  var request=URLRequest(url:url);request.httpMethod="POST";request.timeoutInterval=90
  request.setValue(key,forHTTPHeaderField:"x-goog-api-key");request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("text/event-stream",forHTTPHeaderField:"Accept")
  do{request.httpBody=try JSONSerialization.data(withJSONObject:GeminiPayload.make(text:text,turns:turns))}catch{finish(.failure(OpenAIFailure("无法准备 Gemini 请求，请重试。")));return}
  configuration.timeoutIntervalForRequest=90;configuration.timeoutIntervalForResource=120;configuration.httpShouldSetCookies=false;configuration.urlCache=nil
  let queue=OperationQueue();queue.maxConcurrentOperationCount=1;session=URLSession(configuration:configuration,delegate:self,delegateQueue:queue)
  task=session!.dataTask(with:request);task!.resume()
 }
 func cancel(){task?.cancel();finish(.failure(URLError(.cancelled)))}
 private func isFinished()->Bool{lock.lock();defer{lock.unlock()};return finished}
 private func finish(_ result:Result<String,Error>){
  lock.lock();if finished{lock.unlock();return};finished=true;lock.unlock()
  task=nil;let previous=session;session=nil;previous?.invalidateAndCancel();DispatchQueue.main.async{self.onComplete(result)}
 }
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
 func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping(URLSession.ResponseDisposition)->Void){
  status=(response as? HTTPURLResponse)?.statusCode ?? 0;requestID=(response as? HTTPURLResponse)?.value(forHTTPHeaderField:"x-request-id") ?? ""
  if status==200,!(response.mimeType?.lowercased().hasPrefix("text/event-stream") ?? false){completionHandler(.cancel);finish(.failure(OpenAIFailure("Gemini 没有返回流式响应，请重试。")));return}
  completionHandler(.allow)
 }
 func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data){
  guard !isFinished() else{return}
  if status != 200{if errorBody.count<65536{errorBody.append(data.prefix(65536-errorBody.count))};return}
  for event in parser.feed(data){
   guard !isFinished() else{return}
   if event["error"] != nil{finish(.failure(GeminiErrors.make(status:status,body:event,model:modelID,requestID:requestID,secret:secret)));return}
   if let feedback=event["promptFeedback"] as? [String:Any],let reason=feedback["blockReason"] as? String,reason != "BLOCK_REASON_UNSPECIFIED"{finish(.failure(OpenAIFailure("Gemini 未生成此内容（\(reason)）。请调整提问。",code:reason,model:modelID)));return}
   guard let candidate=(event["candidates"] as? [[String:Any]])?.first else{continue}
   let parts=(candidate["content"] as? [String:Any])?["parts"] as? [[String:Any]] ?? []
   for part in parts where part["thought"] as? Bool != true {
    if let text=part["text"] as? String,output.count<60000{output+=text;DispatchQueue.main.async{self.onDelta(text)}}
   }
   if let reason=candidate["finishReason"] as? String{finishReason=reason}
  }
 }
 func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
  guard !isFinished() else{return}
  if let error=error as? URLError{finish(.failure(OpenAIFailure(error.code == .timedOut ? "连接 Gemini 超时，请检查网络后重试。":"暂时无法连接 Google Gemini，请检查网络后重试。")));return}
  if error != nil{finish(.failure(OpenAIFailure("Gemini 连接异常，请重试。")));return}
  if status != 200{
   let body=(try? JSONSerialization.jsonObject(with:errorBody)) as? [String:Any] ?? [:]
   finish(.failure(GeminiErrors.make(status:status,body:body,model:modelID,requestID:requestID,secret:secret)));return
  }
  guard finishReason=="STOP" else{
   let reason=finishReason ?? "STREAM_INTERRUPTED"
   finish(.failure(OpenAIFailure(reason=="MAX_TOKENS" ? "Gemini 回复达到长度上限，已保留收到的文字，请缩短提问后重试。":"Gemini 回复未完成（\(reason)），请重试或调整提问。",code:reason,model:modelID,requestID:requestID)));return
  }
  if output.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{finish(.failure(OpenAIFailure("Gemini 未返回文字，请重试。")));return}
  finish(.success(output))
 }
}
