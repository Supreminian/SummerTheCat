import Foundation
@main struct Checks {
 static func main(){
  var results:[[String:Any]]=[]
  for fps in [30,60,120]{
   var p=TeaserMotion();p.advance(point:CGPoint(x:0,y:0),dt:1/Double(fps))
   for i in 1...fps{p.advance(point:CGPoint(x:Double(i)*180/Double(fps),y:0),dt:1/Double(fps))}
   results.append(["check":"\(fps)fps moves with bounded independent swings","ok":abs(p.feather)>0.1 && abs(p.feather)<=1.1 && abs(p.bell)<=1.3 && abs(p.feather-p.bell)>0.005])
   let start=p.feather;p.advance(point:CGPoint(x:180,y:0),dt:1/Double(fps));results.append(["check":"\(fps)fps retains inertia after stopping","ok":abs(p.feather)>0.01 && abs(p.feather-start)<0.3])
   for _ in 0..<(fps*6){p.advance(point:CGPoint(x:180,y:0),dt:1/Double(fps))}
   results.append(["check":"\(fps)fps settles without perpetual idle motion","ok":p.settled])
  }
  var jump=TeaserMotion();jump.advance(point:CGPoint(x:0,y:0),dt:1/60);jump.advance(point:CGPoint(x:10000,y:0),dt:1/60)
  results.append(["check":"screen jumps do not produce extreme swings","ok":jump.settled])
  jump.advance(point:CGPoint(x:Double.nan,y:0),dt:1/60);results.append(["check":"invalid input does not poison state","ok":jump.feather.isFinite && jump.bell.isFinite])
  print(String(data:try! JSONSerialization.data(withJSONObject:["ok":results.allSatisfy{$0["ok"] as? Bool == true},"results":results],options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
 }
}
