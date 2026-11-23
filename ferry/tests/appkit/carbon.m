/* SPDX-License-Identifier: GPL-3.0-or-later
 * Smaller pieces real apps stopped at: the Carbon and Accessibility calls
 * Cocoa apps still make (answered as a Mac answers when the thing isn't
 * available), SystemConfiguration's network reachability, and a few AppKit
 * and Foundation methods (services provider, paragraph styles in archives,
 * content borders, cell background styles, resolving links in a URL). The
 * Carbon declarations are written here from Apple's public documentation. */
#import <Cocoa/Cocoa.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <unistd.h>

typedef int32_t OSStatus;
typedef struct { uint32_t signature, id; } EventHotKeyID;
typedef struct { uint32_t high, low; } ProcessSerialNumber;
void *GetApplicationEventTarget(void);
OSStatus InstallEventHandler(void *target, void *handler, unsigned long count, const void *types, void *userData,
                             void **outRef);
OSStatus RegisterEventHotKey(uint32_t keyCode, uint32_t modifiers, EventHotKeyID hotKeyID, void *target,
                             uint32_t options, void **outRef);
OSStatus UnregisterEventHotKey(void *ref);
void *TISCopyCurrentKeyboardInputSource(void);
void *TISGetInputSourceProperty(void *source, CFStringRef key);
extern const CFStringRef kTISPropertyUnicodeKeyLayoutData;
OSStatus UCKeyTranslate(const void *layout, uint16_t keyCode, uint16_t action, uint32_t modifiers, uint32_t kbdType,
                        uint32_t options, uint32_t *deadKeyState, unsigned long max, unsigned long *actualLength,
                        uint16_t *chars);
OSStatus GetCurrentProcess(ProcessSerialNumber *psn);
OSStatus GetProcessPID(const ProcessSerialNumber *psn, pid_t *pid);
OSStatus TransformProcessType(const ProcessSerialNumber *psn, uint32_t type);
Boolean AXIsProcessTrusted(void);
Boolean AXIsProcessTrustedWithOptions(CFDictionaryRef options);
extern const CFStringRef kAXTrustedCheckOptionPrompt;
void *AXUIElementCreateApplication(pid_t pid);
OSStatus AXUIElementCopyAttributeValue(void *element, CFStringRef attribute, CFTypeRef *value);

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        void *handler = NULL, *hotkey = NULL;
        OSStatus r = InstallEventHandler(GetApplicationEventTarget(), NULL, 0, NULL, NULL, &handler);
        printf("event handler %d, ref %s\n", r, handler ? "yes" : "no");
        EventHotKeyID hk = {'FrRy', 1};
        r = RegisterEventHotKey(49, 0x100, hk, GetApplicationEventTarget(), 0, &hotkey);
        printf("hotkey %d, ref %s, unregister %d\n", r, hotkey ? "yes" : "no", UnregisterEventHotKey(hotkey));
        void *source = TISCopyCurrentKeyboardInputSource();
        unsigned long len = 9;
        uint16_t chars[4];
        uint32_t dead = 0;
        printf("input source %s, layout data %s, translate %d (length %lu)\n", source ? "yes" : "no",
               TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) ? "yes" : "none",
               UCKeyTranslate(NULL, 0, 0, 0, 0, 0, &dead, 4, &len, chars), len);
        CFRelease(source);
        ProcessSerialNumber psn;
        pid_t pid = 0;
        GetCurrentProcess(&psn);
        GetProcessPID(&psn, &pid);
        printf("current process is this one: %d, transform %d\n", pid == getpid(), TransformProcessType(&psn, 1));
        NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt : @YES};
        CFTypeRef value = (CFTypeRef)1;
        void *app = AXUIElementCreateApplication(getpid());
        printf("trusted %d, with options %d, attribute %d, value %s\n", AXIsProcessTrusted(),
               AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts),
               AXUIElementCopyAttributeValue(app, CFSTR("AXWindows"), &value), value ? "set" : "NULL");
        CFRelease(app);

        SCNetworkReachabilityRef reach = SCNetworkReachabilityCreateWithName(NULL, "example.org");
        SCNetworkReachabilityFlags flags = 0;
        printf("reachability %d, reachable %d, scheduled %d\n", SCNetworkReachabilityGetFlags(reach, &flags),
               (flags & kSCNetworkReachabilityFlagsReachable) != 0,
               SCNetworkReachabilityScheduleWithRunLoop(reach, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode));
        CFRelease(reach);
        CFStringRef host = SCDynamicStoreCopyComputerName(NULL, NULL);
        printf("computer name %s\n", host && CFStringGetLength(host) ? "yes" : "no");
        CFRelease(host);

        id provider = [[NSObject alloc] init];
        [NSApp setServicesProvider:provider];
        printf("services provider kept %d\n", [NSApp servicesProvider] == provider);
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.alignment = NSTextAlignmentCenter;
        NSData *d = [NSKeyedArchiver archivedDataWithRootObject:ps];
        NSParagraphStyle *back = [NSKeyedUnarchiver unarchiveObjectWithData:d];
        printf("paragraph style archived and back, centred %d\n", back.alignment == NSTextAlignmentCenter);
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w setContentBorderThickness:24 forEdge:NSMinYEdge];
        printf("content border %.0f\n", [w contentBorderThicknessForEdge:NSMinYEdge]);
        NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"x"];
        cell.backgroundStyle = NSBackgroundStyleEmphasized;
        printf("background style %ld\n", (long)cell.backgroundStyle);
        NSURL *tmp = [NSURL fileURLWithPath:@"/tmp/../tmp/."];
        printf("resolved %s\n", [[[tmp URLByResolvingSymlinksInPath] path] UTF8String]);
    }
    return 0;
}
