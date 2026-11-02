import Foundation
// Modern ICNS entries can contain PNG payloads directly.
let source=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
func word(_ value:Int)->Data{var v=UInt32(value).bigEndian;return Data(bytes:&v,count:4)}
var entries=Data()
for (tag,file) in [("icp4","icon_16x16.png"),("icp5","icon_32x32.png"),("icp6","icon_32x32@2x.png"),("ic07","icon_128x128.png"),("ic08","icon_256x256.png"),("ic09","icon_512x512.png"),("ic10","icon_512x512@2x.png")]{
 let png=try Data(contentsOf:source.appendingPathComponent(file));entries.append(Data(tag.utf8));entries.append(word(png.count+8));entries.append(png)
}
var icns=Data("icns".utf8);icns.append(word(entries.count+8));icns.append(entries)
try icns.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
