// Foundation's value types in Swift (freemac 1.230): Date, Data, URL and
// UUID, to and from their NS classes; JSONEncoder and JSONDecoder with
// Codable; FileHandle's Swift methods, as TomatoBar's log uses them;
// String.Encoding; DateComponentsFormatter.
import Foundation

// ---- Date
let epoch = Date(timeIntervalSince1970: 0)
print("1970 from the reference date:", epoch.timeIntervalSinceReferenceDate)
let later = epoch.addingTimeInterval(90)
print("later:", later.timeIntervalSince(epoch), later > epoch, epoch + 90 == later)
let ns: NSDate = later as NSDate
print("as NSDate:", ns.timeIntervalSince1970)
let back = ns as Date
print("and back:", back == later)
let nowish = Date()
print("now is after 2020:", nowish.timeIntervalSince1970 > 1_577_836_800, abs(Date.now.timeIntervalSince(nowish)) < 5)
var sorted = [later, epoch, Date(timeIntervalSince1970: 30)]
sorted.sort()
print("sorted:", sorted.map { $0.timeIntervalSince1970 })

// ---- Data
var d = Data([1, 2, 3])
let copy = d
d.append(4)
d.append(contentsOf: [5, 6])
print("data:", Array(d), "copy unchanged:", Array(copy), d.count)
let slice = d[2..<5]
print("slice keeps its indices:", slice.startIndex, Array(slice), slice[3])
print("base64:", d.base64EncodedString(), Data(base64Encoded: "AQIDBAUG") == d)
let line = "\n".data(using: .utf8)!
let text = "hé".data(using: .utf8)! + line
print("utf8:", Array(text), String(data: text, encoding: .utf8)!.count)
let nsd: NSData = d as NSData
print("as NSData:", nsd.length, (nsd as Data) == d)
print("hashes equal:", Data([1, 2]).hashValue == Data([1, 2]).hashValue)

// ---- URL
let u = URL(string: "tomatobar://startStop?x=1#top")!
print("url:", u.scheme!, u.host!, u.query!, u.fragment!)
let f = URL(fileURLWithPath: "/tmp/some/file.txt")
print("file:", f.path, f.lastPathComponent, f.pathExtension, f.isFileURL)
print("deleting:", f.deletingLastPathComponent().path, f.deletingPathExtension().lastPathComponent)
print("appending:", f.deletingLastPathComponent().appendingPathComponent("other.log").path)
print("components:", f.pathComponents)
print("bad url:", URL(string: "") == nil)
let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
print("caches folder is a file URL:", caches.isFileURL, caches.path.hasSuffix("Caches") || caches.path.contains("cache"))
print("as NSURL:", (f as NSURL).path!, URL(string: "https://example.com/a")! == URL(string: "https://example.com/a")!)

// ---- UUID
let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
print("uuid:", id.uuidString, id == UUID(uuidString: "e621e1f8-c36c-495a-93fc-0c247a3e6e5f"))
let fresh = UUID()
print("fresh:", fresh.uuidString.count, fresh != UUID(), (fresh as NSUUID).uuidString == fresh.uuidString)

// ---- JSON
struct Event: Codable, Equatable {
    var type: String
    var timestamp: Date
    var count: Int
    var ratio: Double
    var tags: [String]
    var note: String?
    var payload: Data
    var link: URL
}
let e = Event(type: "transition", timestamp: Date(timeIntervalSince1970: 1_700_000_000.5), count: 3, ratio: 0.25,
              tags: ["a/b", "c\"d"], note: nil, payload: Data([0xde, 0xad]), link: URL(string: "https://example.com/x")!)
let enc = JSONEncoder()
enc.outputFormatting = .sortedKeys
enc.dateEncodingStrategy = .secondsSince1970
let json = try! enc.encode(e)
print(String(data: json, encoding: .utf8)!)
let dec = JSONDecoder()
dec.dateDecodingStrategy = .secondsSince1970
let e2 = try! dec.decode(Event.self, from: json)
print("round trip:", e2 == e)
enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
print(String(data: try! enc.encode(["z": [1, 2], "a": []]), encoding: .utf8)!)
struct Snake: Codable { var someURLValue: Int; var plain: Bool }
let snakeEnc = JSONEncoder()
snakeEnc.keyEncodingStrategy = .convertToSnakeCase
let sj = try! snakeEnc.encode(Snake(someURLValue: 1, plain: true))
print(String(data: sj, encoding: .utf8)!)
let snakeDec = JSONDecoder()
snakeDec.keyDecodingStrategy = .convertFromSnakeCase
struct Camel: Codable { var someValue: Int; var plain: Bool }
print("snake back:", try! snakeDec.decode(Camel.self, from: "{\"some_value\": 7, \"plain\": false}".data(using: .utf8)!).someValue)
do {
    _ = try JSONDecoder().decode([Int].self, from: "[1, \"two\"]".data(using: .utf8)!)
} catch DecodingError.typeMismatch(let t, let ctx) {
    print("mismatch:", t, ctx.codingPath.map { $0.intValue ?? -1 })
} catch { print("other error", error) }
do {
    _ = try JSONDecoder().decode([Int].self, from: "[1,".data(using: .utf8)!)
} catch DecodingError.dataCorrupted { print("corrupted: yes") } catch { print("other error", error) }
print("unicode:", try! JSONDecoder().decode(String.self, from: "\"\\u00e9\\ud83d\\ude00\"".data(using: .utf8)!))

// ---- FileHandle, as TomatoBar's log writes
let logURL = caches.appendingPathComponent("ferry-values-test.log")
let path = logURL.path
try? FileManager.default.createDirectory(atPath: caches.path, withIntermediateDirectories: true, attributes: nil)
_ = FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
let h = FileHandle(forUpdatingAtPath: path)!
for n in 1...2 {
    try! h.seekToEnd()
    try! h.write(contentsOf: try! JSONEncoder().encode(["n": n]) + line)
    try! h.synchronize()
}
try! h.close()
print("log:", try! String(contentsOf: logURL, encoding: .utf8).split(separator: "\n"))
let readBack = try! Data(contentsOf: logURL)
print("read back:", readBack.count)
try! Data([9, 8, 7]).write(to: logURL, options: .atomic)
print("rewritten:", Array(try! Data(contentsOf: logURL)))
try? FileManager.default.removeItem(atPath: path)

// ---- DateComponentsFormatter, as TomatoBar's timer shows the time left
let tf = DateComponentsFormatter()
tf.unitsStyle = .positional
tf.allowedUnits = [.minute, .second]
tf.zeroFormattingBehavior = .pad
let start = Date(timeIntervalSince1970: 1000)
print("time left:", tf.string(from: start, to: start.addingTimeInterval(25 * 60))!,
      tf.string(from: start, to: start.addingTimeInterval(65))!)
