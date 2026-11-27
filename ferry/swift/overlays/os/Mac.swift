// SPDX-License-Identifier: GPL-3.0-or-later
//
// os_log as an app built on a Mac calls it (freemac 1.260). There, Swift
// sees a log as the Objective-C class OS_os_log (named OSLog) and a level as
// os_log_type_t (named OSLogType), and the os overlay adds "default",
// "info" and os_log(_:dso:log:type:_:) to them. Ferry's own OSLog and
// OSLogType are Swift types; these additions, with the Mac's names and
// shapes, write to the same log. Written for Ferry from Apple's
// documentation of the os module.

extension os_log_type_t {
    public static var `default`: os_log_type_t { os_log_type_t(rawValue: 0x00) }
    public static var info: os_log_type_t { os_log_type_t(rawValue: 0x01) }
    public static var debug: os_log_type_t { os_log_type_t(rawValue: 0x02) }
    public static var error: os_log_type_t { os_log_type_t(rawValue: 0x10) }
    public static var fault: os_log_type_t { os_log_type_t(rawValue: 0x11) }
}

extension OS_os_log {
    public static var `default`: OS_os_log { _ferry_os_log_default() }
    public static var disabled: OS_os_log { _ferry_os_log_disabled() }
    public func isEnabled(type: os_log_type_t) -> Bool { os_log_type_enabled(_ferry_os_log_ref(self), type) }
}

@_disfavoredOverload
public func os_log(_ message: StaticString, dso: UnsafeRawPointer? = nil, log: OS_os_log = .default,
                   type: os_log_type_t = .default, _ args: CVarArg...) {
    message.withUTF8Buffer { buf in
        let format = String(decoding: buf, as: UTF8.self)
        let l = _ferry_os_log_ref(log)
        withVaList(args) { ferry_os_logv(l, type, format, $0) }
    }
}

@_disfavoredOverload
public func os_log(_ type: os_log_type_t, dso: UnsafeRawPointer? = nil, log: OS_os_log = .default,
                   _ message: StaticString, _ args: CVarArg...) {
    message.withUTF8Buffer { buf in
        let format = String(decoding: buf, as: UTF8.self)
        let l = _ferry_os_log_ref(log)
        withVaList(args) { ferry_os_logv(l, type, format, $0) }
    }
}
