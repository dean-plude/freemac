// The Mac services TomatoBar's packages call from Swift (freemac 1.230):
// os's Logger and os_log, ServiceManagement's SMAppService and its older
// calls, as LaunchAtLogin uses them; UserNotifications' center and
// AVFoundation's audio player, as TomatoBar uses them.
import Foundation
import ServiceManagement
import os.log
import UserNotifications
import AVFoundation

// The log mirrors into standard error with OS_ACTIVITY_DT_MODE set; this
// test reads it from standard output.
dup2(1, 2)
setvbuf(stdout, nil, _IONBF, 0)

let logger = Logger(subsystem: "org.freemac.test", category: "main")
let failed = true
logger.error("Failed to \(failed ? "enable" : "disable") launch at login: \("no reason", privacy: .public)")
logger.info("count \(42), hex \(255, format: .hex), ratio \(0.5, format: .fixed(precision: 2)), on \(true)")
logger.debug("not shown without OS_LOG_DEBUG")
logger.notice("padded [\("x", align: .right(columns: 3))]")
os_log("C-style %d %{public}@", log: OSLog(subsystem: "org.freemac.test", category: "c"), type: .info, 7, "seven" as NSString)
os_log("default log")
os_log("disabled", log: .disabled)
print("enabled:", OSLog.default.isEnabled(type: .info), OSLog.disabled.isEnabled(type: .error))

// ---- SMAppService, in this test's own home
let app = SMAppService.mainApp
print("main app:", app.status == .notRegistered)
try! app.register()
print("registered:", app.status == .enabled, SMAppService.mainApp.status == .enabled)
try! app.register()
try! app.unregister()
print("unregistered:", app.status == .notRegistered)
do {
    try app.unregister()
    print("unregistered twice")
} catch {
    print("unregister again fails:", (error as NSError).domain ?? "")
}
let helper = SMAppService.loginItem(identifier: "org.freemac.missing-helper")
print("missing helper:", helper.status == .notFound)
do { try helper.register() } catch { print("can't register a missing helper") }
print("agent:", SMAppService.agent(plistName: "x.plist").status == .notFound)

// ---- the older calls
let jobs = SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: AnyObject]]
print("jobs:", jobs?.count ?? -1)
print("helper switched on:", SMLoginItemSetEnabled("org.freemac.missing-helper" as CFString, true))

// ---- UserNotifications: the center is always there
let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
print("notification center:", center === UNUserNotificationCenter.current())
let content = UNMutableNotificationContent()
content.title = "Time's up"
content.categoryIdentifier = "restStarted"
let skip = UNNotificationAction(identifier: "skipRest", title: "Skip", options: [])
let category = UNNotificationCategory(identifier: "restStarted", actions: [skip], intentIdentifiers: [])
print("category:", category.identifier!, category.actions.count, content.title!)

// ---- AVAudioPlayer, as TomatoBar plays its sounds; FERRY_SOUND_PLAYER is
// a stand-in that ends at once, so each play is over straight away
func wav(seconds: Double) -> Data {
    let rate = 8000, samples = Int(Double(rate) * seconds)
    var d = Data()
    func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + samples); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate); u16(1); u16(8)
    d.append(contentsOf: Array("data".utf8)); u32(samples)
    d.append(contentsOf: [UInt8](repeating: 128, count: samples))
    return d
}
final class Listener: NSObject, AVAudioPlayerDelegate {
    var plays = 0
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("finished:", flag, "loops:", player.numberOfLoops, "still playing:", player.isPlaying)
        exit(0)
    }
}
do {
    _ = try AVAudioPlayer(data: Data(), fileTypeHint: AVFileType.wav.rawValue)
} catch {
    print("empty data can't be played")
}
let player = try! AVAudioPlayer(data: wav(seconds: 0.5), fileTypeHint: AVFileType.wav.rawValue)
print("duration:", player.duration, "type:", AVFileType.wav.rawValue)
player.setVolume(0.5, fadeDuration: 0)
player.numberOfLoops = 2
print("volume:", player.volume, "prepared:", player.prepareToPlay())
let listener = Listener()
player.delegate = listener
print("playing:", player.play(), player.isPlaying)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 10))
print("never finished")
