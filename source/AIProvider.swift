import Foundation

enum AIProvider:String,CaseIterable {
 case gemini,openai
 static var current:AIProvider {get{AIProvider(rawValue:UserDefaults.standard.string(forKey:"aiProvider") ?? "gemini") ?? .gemini}set{UserDefaults.standard.set(newValue.rawValue,forKey:"aiProvider")}}
 var name:String{self == .gemini ? "Google Gemini":"OpenAI"}
 var keychainService:String{self == .gemini ? "local.summerthecat.v30.gemini":OpenAIKeychain.service}
 var defaultModel:String{self == .gemini ? "gemini-3.5-flash-lite":OpenAISettings.defaultModel}
 var models:[String]{self == .gemini ? ["gemini-3.5-flash-lite","gemini-3.8-flash","gemini-2.5-flash-lite","gemini-2.5-flash"]:["gpt-4.1-mini","gpt-6-luna","gpt-6.1-sol","gpt-6-astra"]}
 var modelPreference:String{self == .gemini ? "geminiModel":"openAIModel"}
 var model:String{UserDefaults.standard.string(forKey:modelPreference) ?? defaultModel}
 func setModel(_ model:String){UserDefaults.standard.set(model,forKey:modelPreference)}
 func validModel(_ value:String)->Bool{
  self == .gemini ? value.range(of:"^gemini-[A-Za-z0-9._-]{1,100}$",options:.regularExpression) != nil:OpenAISettings.validModel(value)
 }
 func readKey()throws->String?{try OpenAIKeychain.read(service:keychainService)}
 func makeStream(onDelta:@escaping(String)->Void,onComplete:@escaping(Result<String,Error>)->Void)->ChatStreaming{
  if self == .gemini{return GeminiStream(onDelta:onDelta,onComplete:onComplete)}
  return OpenAIStream(onDelta:onDelta,onComplete:onComplete)
 }
}
