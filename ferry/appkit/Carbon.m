/* SPDX-License-Identifier: GPL-3.0-or-later
 * The few Carbon and Accessibility calls that Cocoa apps still make, served
 * from AppKit's file (Carbon links here, as Cocoa does), written from
 * Apple's public documentation of each call.
 *
 * - Global hotkeys (RegisterEventHotKey), from freemac 1.215 (Ferry
 *   0.41.0): on freemac's own compositor, Strata registers the combination
 *   (AWayfire.m) and each press reaches the app's Carbon event handlers as
 *   kEventHotKeyPressed and then kEventHotKeyReleased, and its global event
 *   monitors (NSEvent.m) as a key-down. Only the combinations the app
 *   registered are ever seen, never other keys. Elsewhere (no Wayfire, or a
 *   Wayfire without Strata) a hotkey is accepted but never pressed, as
 *   before: Wayland doesn't let one app see the keys pressed in another.
 * - Keyboard layouts (TIS..., UCKeyTranslate), from freemac 1.221 (Ferry
 *   0.45.0): the current input source is the layout Strata has selected;
 *   while it is English (US) its key layout data lets UCKeyTranslate turn
 *   key codes into characters (with Shift, Caps Lock and Control). Other
 *   layouts have no layout data, and apps then fall back to their own
 *   tables.
 * - Accessibility (AX...), from freemac 1.215 (Ferry 0.41.0): enough of
 *   the API for a window manager such as Spectacle or ShiftIt to find the
 *   focused app and its focused window, read their titles and move and
 *   resize the window, through Wayfire's window-rules calls. As on a Mac,
 *   this needs the user's say: AXIsProcessTrustedWithOptions with the
 *   prompt option asks once (freemac-allow-control, from freemac's shell),
 *   the answer is kept in ~/.config/freemac/window-control.json, and Dials >
 *   Privacy & Security can turn it off again. Until then every call answers
 *   kAXErrorAPIDisabled, as a Mac does before the user allows the app.
 * - Processes (GetCurrentProcess, TransformProcessType...): the process
 *   itself only. */
#import "AInternal.h"
#import "AWayfire.h"
#include <Carbon/Carbon.h>
#include <math.h>
#include <unistd.h>

/* Something to hand out where Carbon hands out an opaque reference. */
@interface ACarbonRef : NSObject
@end
@implementation ACarbonRef
@end

/* ---- the Carbon Event Manager, as far as hotkeys need it ------------------------ */

@interface ACarbonTarget : NSObject {
@public
    NSMutableArray *handlers;    /* the newest first, as Carbon calls them */
}
@end
@implementation ACarbonTarget
- (instancetype)init
{
    if ((self = [super init]))
        handlers = [[NSMutableArray alloc] init];
    return self;
}
@end

@interface ACarbonHandler : NSObject {
@public
    EventHandlerUPP proc;
    void *userData;
    NSMutableData *types;
    ACarbonTarget *target;       /* not retained: the target keeps the handler */
}
@end
@implementation ACarbonHandler
- (BOOL)wantsClass:(UInt32)cls kind:(UInt32)kind
{
    const EventTypeSpec *t = [types bytes];
    for (NSUInteger i = 0; i < [types length] / sizeof *t; i++)
        if (t[i].eventClass == cls && t[i].eventKind == kind)
            return YES;
    return NO;
}
- (void)dealloc
{
    [types release];
    [super dealloc];
}
@end

@interface ACarbonEvent : NSObject {
@public
    UInt32 cls, kind;
    EventHotKeyID hotKey;
    EventTime time;
}
@end
@implementation ACarbonEvent
@end

/* What a handler is given as its call reference: where it is in the chain,
 * so that CallNextEventHandler can go on from there. */
@interface ACarbonCall : NSObject {
@public
    NSArray *chain;
    NSUInteger index;
    BOOL passedOn;
}
@end
@implementation ACarbonCall
- (void)dealloc
{
    [chain release];
    [super dealloc];
}
@end

static ACarbonTarget *application_target, *dispatcher_target, *monitor_target;

static ACarbonTarget *named_target(ACarbonTarget **slot)
{
    if (!*slot)
        *slot = [[ACarbonTarget alloc] init];
    return *slot;
}

EventTargetRef GetApplicationEventTarget(void) { return (EventTargetRef)named_target(&application_target); }
EventTargetRef GetEventDispatcherTarget(void) { return (EventTargetRef)named_target(&dispatcher_target); }
EventTargetRef GetEventMonitorTarget(void) { return (EventTargetRef)named_target(&monitor_target); }

EventHandlerUPP NewEventHandlerUPP(EventHandlerProcPtr proc) { return proc; }
void DisposeEventHandlerUPP(EventHandlerUPP upp) {}
OSStatus InvokeEventHandlerUPP(EventHandlerCallRef call, EventRef event, void *userData, EventHandlerUPP upp)
{
    return upp ? upp(call, event, userData) : eventNotHandledErr;
}

static BOOL is_target(void *target)
{
    return target && (target == application_target || target == dispatcher_target || target == monitor_target);
}

OSStatus InstallEventHandler(EventTargetRef target, EventHandlerUPP proc, UInt32 count, const EventTypeSpec *types,
                             void *userData, EventHandlerRef *outRef)
{
    ACarbonHandler *h = [[ACarbonHandler alloc] init];
    h->proc = proc;
    h->userData = userData;
    h->types = [[NSMutableData alloc] initWithBytes:types length:types ? count * sizeof *types : 0];
    /* a window's target or another of Carbon's is accepted; only the three
     * above are ever sent anything */
    if (is_target(target)) {
        h->target = (ACarbonTarget *)target;
        [h->target->handlers insertObject:h atIndex:0];
        [h release];
    }
    if (outRef)
        *outRef = (EventHandlerRef)h;
    return noErr;
}
OSStatus RemoveEventHandler(EventHandlerRef ref)
{
    ACarbonHandler *h = (ACarbonHandler *)ref;
    if (!h)
        return paramErr;
    if (h->target)
        [h->target->handlers removeObjectIdenticalTo:h];
    else
        [h release];
    return noErr;
}
OSStatus AddEventTypesToHandler(EventHandlerRef ref, UInt32 count, const EventTypeSpec *types)
{
    if (!ref || (count && !types))
        return paramErr;
    [((ACarbonHandler *)ref)->types appendBytes:types length:count * sizeof *types];
    return noErr;
}
OSStatus RemoveEventTypesFromHandler(EventHandlerRef ref, UInt32 count, const EventTypeSpec *types)
{
    if (!ref || (count && !types))
        return paramErr;
    NSMutableData *kept = [NSMutableData data];
    const EventTypeSpec *have = [((ACarbonHandler *)ref)->types bytes];
    for (NSUInteger i = 0; i < [((ACarbonHandler *)ref)->types length] / sizeof *have; i++) {
        BOOL drop = NO;
        for (UInt32 j = 0; j < count; j++)
            drop |= have[i].eventClass == types[j].eventClass && have[i].eventKind == types[j].eventKind;
        if (!drop)
            [kept appendBytes:&have[i] length:sizeof *have];
    }
    [((ACarbonHandler *)ref)->types setData:kept];
    return noErr;
}

/* Calls the chain's handlers from index on, until one handles the event
 * (answers anything but eventNotHandledErr) or passes it on itself. */
static OSStatus run_chain(NSArray *chain, NSUInteger from, ACarbonEvent *event)
{
    for (NSUInteger i = from; i < [chain count]; i++) {
        ACarbonHandler *h = chain[i];
        if (!h->proc)
            continue;
        ACarbonCall *call = [[ACarbonCall alloc] init];
        call->chain = [chain retain];
        call->index = i;
        OSStatus r = eventNotHandledErr;
        A_REPORTING(r = h->proc((EventHandlerCallRef)call, (EventRef)event, h->userData);)
        BOOL passed = call->passedOn;
        [call release];
        if (passed || r != eventNotHandledErr)
            return r;
    }
    return eventNotHandledErr;
}

OSStatus CallNextEventHandler(EventHandlerCallRef ref, EventRef event)
{
    ACarbonCall *call = (ACarbonCall *)ref;
    if (!call || !event)
        return paramErr;
    call->passedOn = YES;
    return run_chain(call->chain, call->index + 1, (ACarbonEvent *)event);
}

/* The event dispatcher's handlers see an event first, then its target's,
 * then the application's. */
static void send_carbon_event(ACarbonEvent *event, ACarbonTarget *target)
{
    NSMutableArray *chain = [NSMutableArray array];
    NSMutableArray *targets = [NSMutableArray array];
    for (ACarbonTarget *t in @[ named_target(&dispatcher_target), target ?: named_target(&application_target),
                                named_target(&application_target) ])
        if (![targets containsObject:t])
            [targets addObject:t];
    for (ACarbonTarget *t in targets)
        for (ACarbonHandler *h in t->handlers)
            if ([h wantsClass:event->cls kind:event->kind])
                [chain addObject:h];
    if ([chain count])
        run_chain(chain, 0, event);
}

OSStatus GetEventParameter(EventRef ref, EventParamName name, EventParamType type, EventParamType *outType,
                           unsigned long size, unsigned long *outSize, void *data)
{
    ACarbonEvent *event = (ACarbonEvent *)ref;
    if (!event || ![(id)event isKindOfClass:[ACarbonEvent class]])
        return paramErr;
    if (event->cls == kEventClassKeyboard && name == kEventParamDirectObject &&
        (type == typeEventHotKeyID || type == typeWildCard)) {
        if (outType)
            *outType = typeEventHotKeyID;
        if (outSize)
            *outSize = sizeof(EventHotKeyID);
        if (data)
            memcpy(data, &event->hotKey, size < sizeof(EventHotKeyID) ? size : sizeof(EventHotKeyID));
        return noErr;
    }
    return eventParameterNotFoundErr;
}
UInt32 GetEventClass(EventRef ref)
{
    return ref && [(id)ref isKindOfClass:[ACarbonEvent class]] ? ((ACarbonEvent *)ref)->cls : 0;
}
UInt32 GetEventKind(EventRef ref)
{
    return ref && [(id)ref isKindOfClass:[ACarbonEvent class]] ? ((ACarbonEvent *)ref)->kind : 0;
}
EventTime GetEventTime(EventRef ref)
{
    return ref && [(id)ref isKindOfClass:[ACarbonEvent class]] ? ((ACarbonEvent *)ref)->time : 0;
}
EventRef RetainEvent(EventRef ref) { return (EventRef)[(id)ref retain]; }
void ReleaseEvent(EventRef ref) { [(id)ref release]; }

OSStatus CopySymbolicHotKeys(CFArrayRef *out)
{
    if (out)
        *out = (CFArrayRef)[[NSArray alloc] init];
    return noErr;
}

/* ---- global hotkeys --------------------------------------------------------------- */

@interface ACarbonHotKey : NSObject {
@public
    UInt32 keyCode, modifiers;
    EventHotKeyID hotKeyID;
    ACarbonTarget *target;
    int64_t strataID, tag;
}
@end
@implementation ACarbonHotKey
@end

static NSMutableDictionary *hotkeys;        /* tag -> ACarbonHotKey */
static int64_t next_tag = 1;

/* A Mac virtual key code's Linux key number (AMacKeyCode, read backwards). */
static int linux_key_for(UInt32 mac)
{
    static int16_t table[128];
    static BOOL made;
    if (!made) {
        for (int i = 0; i < 128; i++)
            table[i] = -1;
        for (int key = 1; key < 128; key++) {
            unsigned short code = AMacKeyCode((uint16_t)(key + 8));
            if (code < 128 && table[code] < 0)
                table[code] = (int16_t)key;
        }
        table[0] = 30;     /* A */
        made = YES;
    }
    return mac < 128 ? table[mac] : -1;
}

static NSArray *modifier_names(UInt32 m)
{
    NSMutableArray *names = [NSMutableArray array];
    if (m & cmdKey)
        [names addObject:@"command"];
    if (m & (optionKey | (1 << 14)))       /* rightOptionKey */
        [names addObject:@"option"];
    if (m & (controlKey | (1 << 15)))      /* rightControlKey */
        [names addObject:@"control"];
    if (m & (shiftKey | (1 << 13)))        /* rightShiftKey */
        [names addObject:@"shift"];
    return names;
}

static NSEventModifierFlags flags_for(UInt32 m)
{
    NSEventModifierFlags f = 0;
    if (m & cmdKey)
        f |= NSEventModifierFlagCommand;
    if (m & (optionKey | (1 << 14)))
        f |= NSEventModifierFlagOption;
    if (m & (controlKey | (1 << 15)))
        f |= NSEventModifierFlagControl;
    if (m & (shiftKey | (1 << 13)))
        f |= NSEventModifierFlagShift;
    return f;
}

/* The characters a key types, for the key-down a global monitor is given:
 * the letters, digits and function keys hotkeys are made of. */
static NSString *characters_for(UInt32 mac)
{
    static const char ansi[0x33] = "asdfhgzxcv\0bqweryt123465=97-80]ou[ip\rlj'k;\\,/nm.\t `";
    unichar c = 0;
    switch (mac) {
    case 0x7B: c = NSLeftArrowFunctionKey; break;
    case 0x7C: c = NSRightArrowFunctionKey; break;
    case 0x7D: c = NSDownArrowFunctionKey; break;
    case 0x7E: c = NSUpArrowFunctionKey; break;
    case 0x73: c = NSHomeFunctionKey; break;
    case 0x77: c = NSEndFunctionKey; break;
    case 0x74: c = NSPageUpFunctionKey; break;
    case 0x79: c = NSPageDownFunctionKey; break;
    case 0x33: c = NSDeleteCharacter; break;
    case 0x35: c = 0x1b; break;
    case 0x7A: c = NSF1FunctionKey; break;
    case 0x78: c = NSF2FunctionKey; break;
    case 0x63: c = NSF3FunctionKey; break;
    case 0x76: c = NSF4FunctionKey; break;
    case 0x60: c = NSF5FunctionKey; break;
    case 0x61: c = NSF6FunctionKey; break;
    case 0x62: c = NSF7FunctionKey; break;
    case 0x64: c = NSF8FunctionKey; break;
    case 0x65: c = NSF9FunctionKey; break;
    case 0x6D: c = NSF10FunctionKey; break;
    case 0x67: c = NSF11FunctionKey; break;
    case 0x6F: c = NSF12FunctionKey; break;
    default:
        if (mac < sizeof ansi)
            c = (unsigned char)ansi[mac];
    }
    return c ? [NSString stringWithCharacters:&c length:1] : @"";
}

static void hotkey_pressed(int64_t tag)
{
    ACarbonHotKey *hk = [[hotkeys[@(tag)] retain] autorelease];
    if (!hk)
        return;
    EventTime now = [[NSProcessInfo processInfo] systemUptime];
    for (UInt32 kind = kEventHotKeyPressed; kind <= kEventHotKeyReleased; kind++) {
        ACarbonEvent *event = [[ACarbonEvent alloc] init];
        event->cls = kEventClassKeyboard;
        event->kind = kind;
        event->hotKey = hk->hotKeyID;
        event->time = now;
        send_carbon_event(event, hk->target);
        [event release];
    }
    NSString *chars = characters_for(hk->keyCode);
    for (NSEventType type = NSEventTypeKeyDown; type <= NSEventTypeKeyUp; type++) {
        NSEvent *e = [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags_for(hk->modifiers)
                                     timestamp:now windowNumber:0 context:nil characters:chars
                   charactersIgnoringModifiers:chars isARepeat:NO keyCode:(unsigned short)hk->keyCode];
        AGlobalMonitorsDeliver(e);
    }
    AWindowsNeedUpdate();
}

static void hotkeys_unavailable(void)
{
    AWarnOnce("global keyboard shortcuts (the app's shortcut is kept but never pressed)");
}

OSStatus RegisterEventHotKey(UInt32 keyCode, UInt32 modifiers, EventHotKeyID hotKeyID, EventTargetRef target,
                             OptionBits options, EventHotKeyRef *outRef)
{
    if (outRef)
        *outRef = NULL;
    ACarbonHotKey *hk = [[ACarbonHotKey alloc] init];
    hk->keyCode = keyCode;
    hk->modifiers = modifiers;
    hk->hotKeyID = hotKeyID;
    hk->target = is_target(target) ? (ACarbonTarget *)target : named_target(&application_target);
    hk->tag = next_tag++;
    int key = linux_key_for(keyCode);
    NSString *socket = AWayfireAvailable() ? AWayfireHotkeySocket(hotkey_pressed) : nil;
    if (!socket) {
        hotkeys_unavailable();
    } else if (key < 0) {
        [hk release];
        return eventHotKeyInvalidErr;
    } else {
        id reply = AWayfireCall(@"strata/hotkeys/register", @{
            @"key" : @(key),
            @"modifiers" : modifier_names(modifiers),
            @"socket" : socket,
            @"tag" : @(hk->tag),
        });
        NSString *error = AWayfireError(reply);
        if ([error isEqual:@"taken"]) {
            [hk release];
            return eventHotKeyExistsErr;
        }
        if (error && [error hasPrefix:@"No such method"]) {
            hotkeys_unavailable();      /* a Wayfire without Strata */
        } else if (error) {
            [hk release];
            return eventHotKeyInvalidErr;
        } else {
            hk->strataID = [reply[@"id"] longLongValue];
            if (!hotkeys)
                hotkeys = [[NSMutableDictionary alloc] init];
            hotkeys[@(hk->tag)] = hk;
        }
    }
    if (outRef)
        *outRef = (EventHotKeyRef)hk;
    else
        [hk autorelease];
    return noErr;
}

OSStatus UnregisterEventHotKey(EventHotKeyRef ref)
{
    ACarbonHotKey *hk = (ACarbonHotKey *)ref;
    if (!hk)
        return paramErr;
    if (hk->strataID)
        AWayfireCall(@"strata/hotkeys/unregister", @{@"id" : @(hk->strataID)});
    [hotkeys removeObjectForKey:@(hk->tag)];
    [hk release];
    return noErr;
}

/* ---- keyboard input sources (freemac 1.221, Ferry 0.45.0) ---------------------------
 * The current input source is the keyboard layout Strata says is selected
 * (English (US) when there is no Strata to ask). An English (US) source
 * carries key layout data of Ferry's own, which only UCKeyTranslate reads:
 * a mark and a version; the keys themselves are in the tables below. */

@interface ATISInputSource : NSObject {
@public
    NSDictionary *properties;
}
@end
@implementation ATISInputSource
- (void)dealloc
{
    [properties release];
    [super dealloc];
}
- (NSString *)description { return [NSString stringWithFormat:@"<TISInputSource %@>", properties[@"id"]]; }
@end

#define LAYOUT_MARK 0x46525553u /* "FRUS" */
struct ferry_key_layout {
    uint32_t mark, version;
};

/* What each key of an English (US) keyboard types without Shift, by Mac key
 * code; keys that type nothing printable are 0. */
static const unsigned char us_plain[128] = {
    [0x00] = 'a', [0x01] = 's', [0x02] = 'd', [0x03] = 'f', [0x04] = 'h', [0x05] = 'g', [0x06] = 'z', [0x07] = 'x',
    [0x08] = 'c', [0x09] = 'v', [0x0A] = 0xa7, [0x0B] = 'b', [0x0C] = 'q', [0x0D] = 'w', [0x0E] = 'e',
    [0x0F] = 'r', [0x10] = 'y', [0x11] = 't', [0x12] = '1', [0x13] = '2', [0x14] = '3', [0x15] = '4',
    [0x16] = '6', [0x17] = '5', [0x18] = '=', [0x19] = '9', [0x1A] = '7', [0x1B] = '-', [0x1C] = '8',
    [0x1D] = '0', [0x1E] = ']', [0x1F] = 'o', [0x20] = 'u', [0x21] = '[', [0x22] = 'i', [0x23] = 'p',
    [0x25] = 'l', [0x26] = 'j', [0x27] = '\'', [0x28] = 'k', [0x29] = ';', [0x2A] = '\\', [0x2B] = ',',
    [0x2C] = '/', [0x2D] = 'n', [0x2E] = 'm', [0x2F] = '.', [0x32] = '`',
    [0x41] = '.', [0x43] = '*', [0x45] = '+', [0x4B] = '/', [0x4E] = '-', [0x51] = '=', [0x52] = '0',
    [0x53] = '1', [0x54] = '2', [0x55] = '3', [0x56] = '4', [0x57] = '5', [0x58] = '6', [0x59] = '7',
    [0x5B] = '8', [0x5C] = '9',
};
/* ... and with Shift, for the keys that aren't letters. */
static const char us_shifted_from[] = "1234567890-=[]\\;',./`", us_shifted_to[] = "!@#$%^&*()_+{}|:\"<>?~";

/* The control characters the other keys type, as a Mac's layouts give them. */
static UniChar us_special(UInt16 key)
{
    switch (key) {
    case 0x24: return 0x0D;                                    /* Return */
    case 0x4C: return 0x03;                                    /* Enter */
    case 0x30: return 0x09;                                    /* Tab */
    case 0x31: return ' ';
    case 0x33: return 0x08;                                    /* Delete */
    case 0x35: case 0x47: return 0x1B;                         /* Escape, keypad Clear */
    case 0x75: return 0x7F;                                    /* Forward Delete */
    case 0x73: return 0x01;                                    /* Home */
    case 0x77: return 0x04;                                    /* End */
    case 0x74: return 0x0B;                                    /* Page Up */
    case 0x79: return 0x0C;                                    /* Page Down */
    case 0x72: return 0x05;                                    /* Help */
    case 0x7B: return 0x1C;                                    /* the arrows */
    case 0x7C: return 0x1D;
    case 0x7E: return 0x1E;
    case 0x7D: return 0x1F;
    case 0x7A: case 0x78: case 0x63: case 0x76: case 0x60: case 0x61: case 0x62: case 0x64: case 0x65:
    case 0x6D: case 0x67: case 0x6F: case 0x69: case 0x6B: case 0x71: case 0x6A: case 0x40: case 0x4F:
    case 0x50: case 0x5A:
        return 0x10;                                           /* the function keys */
    default: return 0;
    }
}

static NSString *selected_layout_name(void)
{
    id reply = AWayfireCall(@"strata/input-source", nil);
    id names = [reply isKindOfClass:[NSDictionary class]] ? reply[@"names"] : nil;
    if (![names isKindOfClass:[NSArray class]] || ![names count])
        return @"English (US)";
    NSUInteger i = [reply[@"index"] unsignedIntegerValue];
    id name = i < [names count] ? names[i] : nil;
    return [name isKindOfClass:[NSString class]] ? name : @"English (US)";
}

static ATISInputSource *make_source(NSString *name)
{
    ATISInputSource *src = [[ATISInputSource alloc] init];
    BOOL us = [name isEqual:@"English (US)"];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    p[@"name"] = name;
    NSString *compact = [[name componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet]
                                                                        invertedSet]] componentsJoinedByString:@""];
    p[@"id"] = us ? @"com.apple.keylayout.US" : [@"org.freemac.keylayout." stringByAppendingString:compact];
    p[@"languages"] = us ? @[ @"en" ] : @[];
    if (us) {
        struct ferry_key_layout layout = {LAYOUT_MARK, 1};
        p[@"layout"] = [NSData dataWithBytes:&layout length:sizeof layout];
    }
    src->properties = [p copy];
    return src;
}

/* A Mac keeps one object for each input source, so a program may hold the
 * current one without retaining it (ShortcutRecorder does): each source is
 * made once and kept, and handed out retained (freemac 1.224). */
static ATISInputSource *source_named(NSString *name)
{
    static NSMutableDictionary *made;
    @synchronized([ATISInputSource class]) {
        if (!made)
            made = [[NSMutableDictionary alloc] init];
        ATISInputSource *src = made[name];
        if (!src) {
            src = make_source(name);
            made[name] = src;
            [src release];
        }
        return [src retain];
    }
}

static ATISInputSource *current_source(void) { return source_named(selected_layout_name()); }

TISInputSourceRef TISCopyCurrentKeyboardInputSource(void) { return (TISInputSourceRef)current_source(); }
TISInputSourceRef TISCopyCurrentKeyboardLayoutInputSource(void) { return (TISInputSourceRef)current_source(); }
/* Every layout freemac offers types Latin letters, so the current one is
 * also the current ASCII-capable one. */
TISInputSourceRef TISCopyCurrentASCIICapableKeyboardInputSource(void) { return (TISInputSourceRef)current_source(); }
TISInputSourceRef TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void)
{
    return (TISInputSourceRef)current_source();
}
TISInputSourceRef TISCopyInputSourceForLanguage(CFStringRef language)
{
    NSString *l = (NSString *)language;
    if ([l isEqual:@"en"] || [l hasPrefix:@"en-"] || [l hasPrefix:@"en_"])
        return (TISInputSourceRef)source_named(@"English (US)");
    return NULL;
}

static NSArray *all_sources(void)
{
    NSMutableArray *list = [NSMutableArray array];
    id reply = AWayfireCall(@"strata/input-source", nil);
    id names = [reply isKindOfClass:[NSDictionary class]] ? reply[@"names"] : nil;
    if (![names isKindOfClass:[NSArray class]] || ![names count])
        names = @[ @"English (US)" ];
    for (id n in names)
        if ([n isKindOfClass:[NSString class]])
            [list addObject:[source_named(n) autorelease]];
    return list;
}

CFArrayRef TISCreateInputSourceList(CFDictionaryRef filter, Boolean includeAllInstalled)
{
    NSMutableArray *out = [[NSMutableArray alloc] init];
    NSDictionary *want = (NSDictionary *)filter;
    for (ATISInputSource *src in all_sources()) {
        BOOL ok = YES;
        for (id key in want) {
            id have = (id)TISGetInputSourceProperty((TISInputSourceRef)src, (CFStringRef)key);
            if (!have || ![have isEqual:want[key]])
                ok = NO;
        }
        if (ok)
            [out addObject:src];
    }
    return (CFArrayRef)out;
}

CFArrayRef TISCreateASCIICapableInputSourceList(void) { return TISCreateInputSourceList(NULL, false); }

/* Choosing the layout is the user's, in Topline. */
OSStatus TISSelectInputSource(TISInputSourceRef source) { return paramErr; }

CFTypeID TISInputSourceGetTypeID(void) { return (CFTypeID)(uintptr_t)[ATISInputSource class]; }

void *TISGetInputSourceProperty(TISInputSourceRef ref, CFStringRef key)
{
    ATISInputSource *src = (ATISInputSource *)ref;
    if (!src || ![src isKindOfClass:[ATISInputSource class]] || !key)
        return NULL;
    NSString *k = (NSString *)key;
    NSDictionary *p = src->properties;
    if ([k isEqual:(NSString *)kTISPropertyUnicodeKeyLayoutData])
        return p[@"layout"];
    if ([k isEqual:(NSString *)kTISPropertyInputSourceID])
        return p[@"id"];
    if ([k isEqual:(NSString *)kTISPropertyLocalizedName])
        return p[@"name"];
    if ([k isEqual:(NSString *)kTISPropertyInputSourceType])
        return (void *)kTISTypeKeyboardLayout;
    if ([k isEqual:(NSString *)kTISPropertyInputSourceCategory])
        return (void *)kTISCategoryKeyboardInputSource;
    if ([k isEqual:(NSString *)kTISPropertyInputSourceLanguages])
        return p[@"languages"];
    if ([k isEqual:(NSString *)kTISPropertyInputSourceIsASCIICapable] ||
        [k isEqual:(NSString *)kTISPropertyInputSourceIsEnabled] ||
        [k isEqual:(NSString *)kTISPropertyInputSourceIsSelectCapable])
        return (void *)kCFBooleanTrue;
    if ([k isEqual:(NSString *)kTISPropertyInputSourceIsSelected])
        return (void *)([p[@"name"] isEqual:selected_layout_name()] ? kCFBooleanTrue : kCFBooleanFalse);
    return NULL;
}

/* The characters a key types, from Ferry's English (US) layout data. The
 * modifier state is Carbon's modifier bits shifted right by 8. Option types
 * what the key types without it, and no key is a dead key. Caps Lock makes
 * letters capitals with or without Shift, as on a Mac. */
OSStatus UCKeyTranslate(const UCKeyboardLayout *layoutPtr, UInt16 key, UInt16 action, UInt32 modifiers,
                        UInt32 kbdType, OptionBits options, UInt32 *deadKeyState, UniCharCount max,
                        UniCharCount *actualLength, UniChar *chars)
{
    const struct ferry_key_layout *layout = (const struct ferry_key_layout *)layoutPtr;
    if (actualLength)
        *actualLength = 0;
    if (!layout || layout->mark != LAYOUT_MARK || !deadKeyState || !actualLength || (max && !chars) ||
        action > kUCKeyActionDisplay)
        return paramErr;
    *deadKeyState = 0;
    if (action == kUCKeyActionUp || key >= 128)
        return noErr;
    BOOL shift = (modifiers & ((shiftKey | rightShiftKey) >> 8)) != 0;
    BOOL caps = (modifiers & (alphaLock >> 8)) != 0;
    BOOL control = (modifiers & ((controlKey | rightControlKey) >> 8)) != 0;
    UniChar c = us_plain[key];
    if (!c)
        c = us_special(key);
    else if (c >= 'a' && c <= 'z') {
        if (control && action != kUCKeyActionDisplay)
            c = (UniChar)(c - 'a' + 1);
        else if (shift || caps)
            c = (UniChar)(c - 'a' + 'A');
    } else if (shift && key < 0x41) {
        const char *at = c < 128 ? strchr(us_shifted_from, (int)c) : NULL;
        if (at)
            c = (UniChar)(unsigned char)us_shifted_to[at - us_shifted_from];
        else if (c == 0xa7)
            c = 0xb1; /* the ISO key: section sign, and plus-minus with Shift */
    }
    if (!c || max < 1)
        return noErr;
    chars[0] = c;
    *actualLength = 1;
    return noErr;
}

/* An ANSI keyboard (40 among the keyboard type numbers). */
uint8_t LMGetKbdType(void) { return 40; }

/* ---- the system's own hotkeys and the keyboard's state ------------------------------- */

static OptionBits symbolic_mode;
void *PushSymbolicHotKeyMode(OptionBits options)
{
    OptionBits *token = malloc(sizeof *token);
    if (token)
        *token = symbolic_mode;
    symbolic_mode = options;
    return token;
}
void PopSymbolicHotKeyMode(void *token)
{
    if (token) {
        symbolic_mode = *(OptionBits *)token;
        free(token);
    }
}
OptionBits GetSymbolicHotKeyMode(void) { return symbolic_mode; }

/* NSEvent's modifier flags in Carbon's bits. */
UInt32 GetCurrentEventKeyModifiers(void)
{
    NSEventModifierFlags f = [NSEvent modifierFlags];
    UInt32 m = 0;
    if (f & NSEventModifierFlagCommand)
        m |= cmdKey;
    if (f & NSEventModifierFlagShift)
        m |= shiftKey;
    if (f & NSEventModifierFlagCapsLock)
        m |= alphaLock;
    if (f & NSEventModifierFlagOption)
        m |= optionKey;
    if (f & NSEventModifierFlagControl)
        m |= controlKey;
    return m;
}
UInt32 GetCurrentKeyModifiers(void) { return GetCurrentEventKeyModifiers(); }
/* Which keys are held: Wayland tells an app only of the keys pressed in its
 * own windows, which it hears as events, so none are reported here. */
void GetKeys(KeyMap keys)
{
    if (keys)
        memset(keys, 0, sizeof(KeyMap));
}

int16_t GetMBarHeight(void) { return 0; }

/* ---- processes ----------------------------------------------------------------- */

/* The one process an app sees is itself, numbered kCurrentProcess. */
static BOOL is_self(const ProcessSerialNumber *psn)
{
    return psn && psn->highLongOfPSN == 0 && psn->lowLongOfPSN == kCurrentProcess;
}
OSErr GetCurrentProcess(ProcessSerialNumber *psn)
{
    if (!psn)
        return paramErr;
    psn->highLongOfPSN = 0;
    psn->lowLongOfPSN = kCurrentProcess;
    return noErr;
}
OSErr GetFrontProcess(ProcessSerialNumber *psn) { return GetCurrentProcess(psn); }
/* From kNoProcess, the app itself; after it, no more. */
OSErr GetNextProcess(ProcessSerialNumber *psn)
{
    if (!psn)
        return paramErr;
    if (psn->highLongOfPSN == 0 && psn->lowLongOfPSN == kNoProcess)
        return GetCurrentProcess(psn);
    psn->highLongOfPSN = 0;
    psn->lowLongOfPSN = kNoProcess;
    return procNotFound;
}
OSStatus GetProcessPID(const ProcessSerialNumber *psn, pid_t *pid)
{
    if (!pid)
        return paramErr;
    if (!is_self(psn))
        return procNotFound;
    *pid = getpid();
    return noErr;
}
OSStatus GetProcessForPID(pid_t pid, ProcessSerialNumber *psn)
{
    return pid == getpid() ? GetCurrentProcess(psn) : procNotFound;
}
OSErr SameProcess(const ProcessSerialNumber *a, const ProcessSerialNumber *b, Boolean *result)
{
    if (!a || !b || !result)
        return paramErr;
    *result = a->highLongOfPSN == b->highLongOfPSN && a->lowLongOfPSN == b->lowLongOfPSN;
    return noErr;
}
static NSString *process_name(void)
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *k in @[ @"CFBundleName", @"CFBundleExecutable" ])
        if ([info[k] isKindOfClass:[NSString class]] && [info[k] length])
            return info[k];
    return [[NSProcessInfo processInfo] processName];
}
/* The app's name (as a Pascal string, if asked for), its type 'APPL' and
 * the creator code in its Info.plist ('????' when it has none). */
OSErr GetProcessInformation(const ProcessSerialNumber *psn, ProcessInfoRec *info)
{
    if (!info)
        return paramErr;
    if (!is_self(psn))
        return procNotFound;
    @autoreleasepool {
        if (info->processName) {
            const char *name = [process_name() UTF8String] ?: "";
            size_t n = strlen(name);
            if (n > 31)
                n = 31;
            info->processName[0] = (unsigned char)n;
            memcpy(info->processName + 1, name, n);
        }
        info->processNumber = *psn;
        info->processType = 'APPL';
        NSString *creator = [[NSBundle mainBundle] infoDictionary][@"CFBundleSignature"];
        OSType sig = 0x3f3f3f3f; /* '????' */
        if ([creator isKindOfClass:[NSString class]] && [creator length] == 4) {
            const char *c = [creator UTF8String];
            if (strlen(c) == 4)
                sig = ((OSType)(unsigned char)c[0] << 24) | ((OSType)(unsigned char)c[1] << 16) |
                      ((OSType)(unsigned char)c[2] << 8) | (unsigned char)c[3];
        }
        info->processSignature = sig;
        info->processMode = modeCanBackground | modeHighLevelEventAware | modeNeedSuspendResume;
        info->processLocation = NULL;
        info->processSize = info->processFreeMem = 0;
        info->processLauncher.highLongOfPSN = 0;
        info->processLauncher.lowLongOfPSN = kNoProcess;
        info->processLaunchDate = info->processActiveTime = 0;
        if (info->processAppRef) {
            NSString *path = [[NSBundle mainBundle] bundlePath];
            if (FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation], info->processAppRef, NULL) != noErr)
                memset(info->processAppRef, 0, sizeof(FSRef));
        }
    }
    return noErr;
}
OSStatus CopyProcessName(const ProcessSerialNumber *psn, CFStringRef *name)
{
    if (!name)
        return paramErr;
    if (!is_self(psn))
        return procNotFound;
    *name = (CFStringRef)[process_name() copy];
    return noErr;
}
/* The app's activation policy, as a Mac changes it (freemac 1.224, Ferry
 * 0.48.0). */
OSStatus TransformProcessType(const ProcessSerialNumber *psn, UInt32 type)
{
    if (!is_self(psn))
        return procNotFound;
    [NSApplication sharedApplication];
    if (type == kProcessTransformToForegroundApplication)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    else if (type == kProcessTransformToUIElementApplication)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    else if (type == kProcessTransformToBackgroundApplication)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    return noErr;
}
OSErr SetFrontProcess(const ProcessSerialNumber *psn) { return is_self(psn) ? noErr : procNotFound; }
OSErr SetFrontProcessWithOptions(const ProcessSerialNumber *psn, OptionBits options) { return SetFrontProcess(psn); }
OSErr ShowHideProcess(const ProcessSerialNumber *psn, Boolean visible)
{
    if (!is_self(psn))
        return procNotFound;
    if (visible)
        [NSApp unhide:nil];
    else
        [NSApp hide:nil];
    return noErr;
}
Boolean IsProcessVisible(const ProcessSerialNumber *psn) { return is_self(psn) && ![NSApp isHidden]; }
/* The keys a Mac answers for the app itself. */
CFDictionaryRef ProcessInformationCopyDictionary(const ProcessSerialNumber *psn, UInt32 mask)
{
    if (!is_self(psn))
        return NULL;
    @autoreleasepool {
        NSBundle *b = [NSBundle mainBundle];
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"pid"] = @(getpid());
        d[@"CFBundleName"] = process_name();
        if ([b bundleIdentifier])
            d[@"CFBundleIdentifier"] = [b bundleIdentifier];
        if ([b executablePath])
            d[@"CFBundleExecutable"] = [b executablePath];
        if ([b bundlePath])
            d[@"BundlePath"] = [b bundlePath];
        d[@"FileType"] = @"APPL";
        return (CFDictionaryRef)[d copy];
    }
}
/* No other application can be launched or ended this way here. */
OSErr LaunchApplication(LaunchPBPtr params) { return procNotFound; }
OSErr KillProcess(const ProcessSerialNumber *psn) { return procNotFound; }
const char *GetMacOSStatusCommentString(OSStatus err) { return ""; }
const char *GetMacOSStatusErrorString(OSStatus err) { return ""; }

/* ---- Accessibility: the user's say ------------------------------------------------ */

/* The app as the user's answer is kept: its bundle identifier, or its
 * program's path when it isn't in a bundle. */
static NSString *app_key(void)
{
    NSBundle *b = [NSBundle mainBundle];
    NSString *identifier = [b bundleIdentifier];
    if ([identifier length])
        return identifier;
    NSString *exe = [b executablePath] ?: [[[NSProcessInfo processInfo] arguments] firstObject];
    return [exe length] ? [exe stringByStandardizingPath] : [[NSProcessInfo processInfo] processName];
}

static NSString *app_name(void)
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *k in @[ @"CFBundleDisplayName", @"CFBundleName" ])
        if ([info[k] isKindOfClass:[NSString class]] && [info[k] length])
            return info[k];
    return [[NSProcessInfo processInfo] processName];
}

static NSString *grants_path(void)
{
    const char *config = getenv("XDG_CONFIG_HOME");
    NSString *base = config && *config ? @(config) : [NSHomeDirectory() stringByAppendingPathComponent:@".config"];
    return [base stringByAppendingPathComponent:@"freemac/window-control.json"];
}

/* 1 allowed, 0 not allowed, -1 not asked yet. */
static int stored_answer(void)
{
    NSData *d = [NSData dataWithContentsOfFile:grants_path()];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    id apps = [j isKindOfClass:[NSDictionary class]] ? j[@"apps"] : nil;
    id entry = [apps isKindOfClass:[NSDictionary class]] ? apps[app_key()] : nil;
    id allowed = [entry isKindOfClass:[NSDictionary class]] ? entry[@"allowed"] : nil;
    if (![allowed isKindOfClass:[NSNumber class]])
        return -1;
    return [allowed boolValue] ? 1 : 0;
}

/* Asks the user, once, with freemac's own dialog (freemac-allow-control,
 * which keeps the answer). The app is told it isn't trusted meanwhile, as
 * on a Mac, and finds out by asking again. */
static void ask_user(void)
{
    static BOOL asked;
    if (asked)
        return;
    asked = YES;
    const char *forced = getenv("FERRY_ACCESS_ASKER");
    const char *wl = getenv("WAYLAND_DISPLAY"), *x = getenv("DISPLAY");
    if (!(forced && *forced) && !(wl && *wl) && !(x && *x))
        return;    /* no display to ask on */
    char *found = forced && *forced ? NULL : g_find_program_in_path("freemac-allow-control");
    NSString *asker = forced && *forced ? @(forced) : found ? @(found) : nil;
    if (found)
        g_free(found);
    if (!asker) {
        fflush(stdout);
        fprintf(stderr, "AppKit (Ferry): can't ask whether %s may control other windows "
                        "(freemac-allow-control isn't installed)\n", [app_name() UTF8String]);
        return;
    }
    char *argv[] = {(char *)[asker fileSystemRepresentation], "--app-id", (char *)[app_key() UTF8String], "--name",
                    (char *)[app_name() UTF8String], NULL};
    GError *error = NULL;
    g_spawn_async(NULL, argv, NULL, G_SPAWN_STDOUT_TO_DEV_NULL, NULL, NULL, NULL, &error);
    if (error)
        g_error_free(error);
}

Boolean AXIsProcessTrusted(void) { return stored_answer() == 1; }

Boolean AXIsProcessTrustedWithOptions(CFDictionaryRef options)
{
    int answer = stored_answer();
    id prompt = options ? [(NSDictionary *)options objectForKey:(id)kAXTrustedCheckOptionPrompt] : nil;
    if (answer < 0 && [prompt respondsToSelector:@selector(boolValue)] && [prompt boolValue])
        ask_user();
    return answer == 1;
}

/* Before 10.9 a Mac had one switch for every app; here it is this app's. */
Boolean AXAPIEnabled(void) { return AXIsProcessTrusted(); }

/* ---- Accessibility: elements and values ------------------------------------------- */

enum { AX_SYSTEM_WIDE, AX_APPLICATION, AX_WINDOW };

@interface AAXElement : NSObject {
@public
    int kind;
    pid_t pid;              /* the application's, 0 when only its app id is known */
    NSString *appID;
    int64_t view;           /* the window's Wayfire view */
}
@end
@implementation AAXElement
- (BOOL)isEqual:(id)o
{
    if (o == self)
        return YES;
    if (![o isKindOfClass:[AAXElement class]])
        return NO;
    AAXElement *e = o;
    if (e->kind != kind)
        return NO;
    if (kind == AX_WINDOW)
        return e->view == view;
    if (kind == AX_APPLICATION)
        return (pid && e->pid == pid) || (!pid && !e->pid && [appID isEqual:e->appID]);
    return YES;
}
- (NSUInteger)hash { return (NSUInteger)kind * 31 + (NSUInteger)(kind == AX_WINDOW ? view : pid); }
- (CFTypeID)_ferryCFTypeID { return (CFTypeID)[AAXElement class]; }
- (NSString *)description
{
    static const char *names[] = {"system-wide", "application", "window"};
    return [NSString stringWithFormat:@"<AXUIElement %s pid %d view %lld>", names[kind], (int)pid, (long long)view];
}
- (void)dealloc
{
    [appID release];
    [super dealloc];
}
@end

@interface AAXValue : NSObject {
@public
    AXValueType type;
    union {
        CGPoint point;
        CGSize size;
        CGRect rect;
        CFRange range;
        AXError error;
    } v;
}
@end
@implementation AAXValue
- (CFTypeID)_ferryCFTypeID { return (CFTypeID)[AAXValue class]; }
- (BOOL)isEqual:(id)o
{
    return [o isKindOfClass:[AAXValue class]] && ((AAXValue *)o)->type == type &&
           !memcmp(&((AAXValue *)o)->v, &v, sizeof v);
}
- (NSUInteger)hash { return type; }
- (NSString *)description
{
    switch (type) {
    case kAXValueTypeCGPoint: return [NSString stringWithFormat:@"<AXValue point {%g, %g}>", v.point.x, v.point.y];
    case kAXValueTypeCGSize:
        return [NSString stringWithFormat:@"<AXValue size {%g, %g}>", v.size.width, v.size.height];
    default: return [NSString stringWithFormat:@"<AXValue type %u>", type];
    }
}
@end

static size_t value_size(AXValueType type)
{
    switch (type) {
    case kAXValueTypeCGPoint: return sizeof(CGPoint);
    case kAXValueTypeCGSize: return sizeof(CGSize);
    case kAXValueTypeCGRect: return sizeof(CGRect);
    case kAXValueTypeCFRange: return sizeof(CFRange);
    case kAXValueTypeAXError: return sizeof(AXError);
    default: return 0;
    }
}

CFTypeID AXValueGetTypeID(void) { return (CFTypeID)[AAXValue class]; }
AXValueRef AXValueCreate(AXValueType type, const void *value)
{
    size_t n = value_size(type);
    if (!n || !value)
        return NULL;
    AAXValue *v = [[AAXValue alloc] init];
    v->type = type;
    memcpy(&v->v, value, n);
    return (AXValueRef)v;
}
AXValueType AXValueGetType(AXValueRef value)
{
    return value && [(id)value isKindOfClass:[AAXValue class]] ? ((AAXValue *)value)->type : kAXValueTypeIllegal;
}
Boolean AXValueGetValue(AXValueRef value, AXValueType type, void *out)
{
    if (!value || ![(id)value isKindOfClass:[AAXValue class]] || ((AAXValue *)value)->type != type || !out)
        return false;
    memcpy(out, &((AAXValue *)value)->v, value_size(type));
    return true;
}

CFTypeID AXUIElementGetTypeID(void) { return (CFTypeID)[AAXElement class]; }

static AAXElement *new_element(int kind, pid_t pid, NSString *appID, int64_t view)
{
    AAXElement *e = [[AAXElement alloc] init];
    e->kind = kind;
    e->pid = pid;
    e->appID = [appID copy];
    e->view = view;
    return e;
}

AXUIElementRef AXUIElementCreateSystemWide(void) { return (AXUIElementRef)new_element(AX_SYSTEM_WIDE, 0, nil, 0); }
AXUIElementRef AXUIElementCreateApplication(pid_t pid)
{
    return (AXUIElementRef)new_element(AX_APPLICATION, pid, nil, 0);
}

/* ---- Accessibility: the windows, from Wayfire -------------------------------------- */

/* Where a window was last put, kept a second: Wayfire may still report the
 * old place until the app has drawn the new one, and a window manager
 * usually sets the size, then the position, then the size again. */
@interface APendingPlace : NSObject {
@public
    NSRect local;
    int64_t output;
    NSTimeInterval when;
}
@end
@implementation APendingPlace
@end
static NSMutableDictionary *pending_places;

static NSTimeInterval uptime(void) { return [[NSProcessInfo processInfo] systemUptime]; }

static NSRect json_rect(id j)
{
    if (![j isKindOfClass:[NSDictionary class]])
        return NSZeroRect;
    return NSMakeRect([j[@"x"] doubleValue], [j[@"y"] doubleValue], [j[@"width"] doubleValue],
                      [j[@"height"] doubleValue]);
}

static BOOL is_window(id v)
{
    if (![v isKindOfClass:[NSDictionary class]])
        return NO;
    id kind = v[@"role"] ?: v[@"type"];
    id mapped = v[@"mapped"];
    return [kind isEqual:@"toplevel"] && (!mapped || [mapped boolValue]);
}

static NSArray *wayfire_windows(void)
{
    id list = AWayfireCall(@"window-rules/list-views", nil);
    if (![list isKindOfClass:[NSArray class]])
        return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (id v in list)
        if (is_window(v))
            [out addObject:v];
    /* the most recently focused first */
    [out sortUsingComparator:^NSComparisonResult(id a, id b) {
        double ta = [a[@"last-focus-timestamp"] doubleValue], tb = [b[@"last-focus-timestamp"] doubleValue];
        return ta > tb ? NSOrderedAscending : ta < tb ? NSOrderedDescending : NSOrderedSame;
    }];
    return out;
}

static NSDictionary *window_by_id(NSArray *windows, int64_t view)
{
    for (NSDictionary *v in windows)
        if ([v[@"id"] longLongValue] == view)
            return v;
    return nil;
}

/* {view id: process id} from Strata, or nil (plain Wayfire doesn't say). */
static NSDictionary *window_pids(void)
{
    id reply = AWayfireCall(@"strata/view-pids", nil);
    id views = [reply isKindOfClass:[NSDictionary class]] ? reply[@"views"] : nil;
    if (![views isKindOfClass:[NSArray class]])
        return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (id v in views)
        if ([v isKindOfClass:[NSDictionary class]] && v[@"id"] && v[@"pid"])
            out[@([v[@"id"] longLongValue])] = v[@"pid"];
    return out;
}

static int64_t focused_view(void)
{
    id reply = AWayfireCall(@"window-rules/get-focused-view", nil);
    id info = [reply isKindOfClass:[NSDictionary class]] ? reply[@"info"] : nil;
    return is_window(info) ? [info[@"id"] longLongValue] : 0;
}

static BOOL belongs_to(NSDictionary *window, AAXElement *app, NSDictionary *pids)
{
    if (app->pid && pids)
        return [pids[@([window[@"id"] longLongValue])] intValue] == app->pid;
    return app->appID && [window[@"app-id"] isEqual:app->appID];
}

static AAXElement *application_of(NSDictionary *window, NSDictionary *pids)
{
    pid_t pid = pids ? [pids[@([window[@"id"] longLongValue])] intValue] : 0;
    id appID = [window[@"app-id"] isKindOfClass:[NSString class]] ? window[@"app-id"] : nil;
    return [new_element(AX_APPLICATION, pid, appID, 0) autorelease];
}

static NSArray *windows_of(AAXElement *app, NSArray *windows)
{
    NSDictionary *pids = app->pid ? window_pids() : nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *v in windows)
        if (belongs_to(v, app, pids))
            [out addObject:v];
    return out;
}

static NSDictionary *output_by_id(NSArray *outputs, int64_t output)
{
    for (NSDictionary *o in outputs)
        if ([o[@"id"] longLongValue] == output)
            return o;
    return [outputs firstObject];
}

/* A window's place in Wayfire: its output and its rectangle there. */
static NSRect local_place(NSDictionary *window, int64_t *output)
{
    int64_t view = [window[@"id"] longLongValue];
    APendingPlace *p = pending_places[@(view)];
    if (p && uptime() - p->when < 1.0) {
        *output = p->output;
        return p->local;
    }
    *output = [window[@"output-id"] longLongValue];
    return json_rect(window[@"geometry"]);
}

/* The Accessibility API's rectangle: from the main display's top left,
 * with y running down. */
static NSRect ax_frame(NSDictionary *window, NSArray *outputs)
{
    int64_t output;
    NSRect r = local_place(window, &output);
    NSRect main = [[outputs firstObject][@"frame"] rectValue];
    NSRect of = [output_by_id(outputs, output)[@"frame"] rectValue];
    r.origin.x += of.origin.x - main.origin.x;
    r.origin.y += of.origin.y - main.origin.y;
    return r;
}

static AXError put_window(NSDictionary *window, NSArray *outputs, NSRect ax)
{
    if (ax.size.width < 1 || ax.size.height < 1 || !isfinite(ax.origin.x) || !isfinite(ax.origin.y))
        return kAXErrorIllegalArgument;
    int64_t from;
    local_place(window, &from);
    NSRect main = [[outputs firstObject][@"frame"] rectValue];
    NSRect layout = NSOffsetRect(ax, main.origin.x, main.origin.y);
    NSPoint centre = NSMakePoint(NSMidX(layout), NSMidY(layout));
    NSDictionary *to = nil;
    for (NSDictionary *o in outputs)
        if (NSPointInRect(centre, [o[@"frame"] rectValue]))
            to = o;
    for (NSDictionary *o in outputs)
        if (!to && NSPointInRect(layout.origin, [o[@"frame"] rectValue]))
            to = o;
    if (!to)
        to = output_by_id(outputs, from);
    NSRect of = [to[@"frame"] rectValue];
    NSRect local = NSMakeRect(round(layout.origin.x - of.origin.x), round(layout.origin.y - of.origin.y),
                              round(layout.size.width), round(layout.size.height));
    int64_t view = [window[@"id"] longLongValue], output = [to[@"id"] longLongValue];
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary:@{
        @"id" : @(view),
        @"geometry" : @{
            @"x" : @((long long)local.origin.x),
            @"y" : @((long long)local.origin.y),
            @"width" : @((long long)local.size.width),
            @"height" : @((long long)local.size.height),
        },
    }];
    if (output != from)
        data[@"output_id"] = @(output);
    id reply = AWayfireCall(@"window-rules/configure-view", data);
    if (!reply)
        return kAXErrorCannotComplete;
    if (AWayfireError(reply))
        return kAXErrorInvalidUIElement;
    if (!pending_places)
        pending_places = [[NSMutableDictionary alloc] init];
    APendingPlace *p = [[APendingPlace alloc] init];
    p->local = local;
    p->output = output;
    p->when = uptime();
    pending_places[@(view)] = p;
    [p release];
    return kAXErrorSuccess;
}

static id copy_value(id value) { return value ? [value retain] : nil; }

static id ax_bool(BOOL b) { return b ? (id)kCFBooleanTrue : (id)kCFBooleanFalse; }

static AXValueRef point_value(CGPoint p) { return AXValueCreate(kAXValueTypeCGPoint, &p); }
static AXValueRef size_value(CGSize s) { return AXValueCreate(kAXValueTypeCGSize, &s); }

/* Every call checks the user's say first, then that there is a Wayfire to
 * ask. */
static AXError usable(AXUIElementRef element)
{
    if (!element || ![(id)element isKindOfClass:[AAXElement class]])
        return kAXErrorIllegalArgument;
    if (!AXIsProcessTrusted())
        return kAXErrorAPIDisabled;
    if (!AWayfireAvailable())
        return kAXErrorCannotComplete;
    return kAXErrorSuccess;
}

static NSArray *names_for(AAXElement *e)
{
    switch (e->kind) {
    case AX_SYSTEM_WIDE: return @[ @"AXRole", @"AXFocusedApplication", @"AXFocusedUIElement" ];
    case AX_APPLICATION:
        return @[ @"AXRole", @"AXTitle", @"AXWindows", @"AXFocusedWindow", @"AXMainWindow", @"AXFrontmost",
                  @"AXHidden" ];
    default:
        return @[ @"AXRole", @"AXSubrole", @"AXTitle", @"AXPosition", @"AXSize", @"AXMinimized", @"AXFullScreen",
                  @"AXMain", @"AXFocused", @"AXParent" ];
    }
}

AXError AXUIElementCopyAttributeNames(AXUIElementRef element, CFArrayRef *names)
{
    AXError r = usable(element);
    if (r)
        return r;
    if (names)
        *names = (CFArrayRef)[names_for((AAXElement *)element) copy];
    return kAXErrorSuccess;
}

static AXError window_attribute(AAXElement *e, NSString *a, id *out)
{
    NSArray *windows = wayfire_windows();
    if (!windows)
        return kAXErrorCannotComplete;
    NSDictionary *w = window_by_id(windows, e->view);
    if (!w)
        return kAXErrorInvalidUIElement;
    if ([a isEqual:@"AXRole"])
        *out = [@"AXWindow" retain];
    else if ([a isEqual:@"AXSubrole"]) {
        id parent = w[@"parent"];
        BOOL dialog = [parent isKindOfClass:[NSNumber class]] && [parent longLongValue] >= 0 &&
                      window_by_id(windows, [parent longLongValue]);
        *out = [(dialog ? @"AXDialog" : @"AXStandardWindow") retain];
    } else if ([a isEqual:@"AXTitle"])
        *out = [([w[@"title"] isKindOfClass:[NSString class]] ? w[@"title"] : @"") retain];
    else if ([a isEqual:@"AXPosition"] || [a isEqual:@"AXSize"]) {
        NSArray *outputs = AWayfireOutputs();
        if (!outputs)
            return kAXErrorCannotComplete;
        NSRect f = ax_frame(w, outputs);
        *out = [a isEqual:@"AXPosition"] ? (id)point_value(f.origin) : (id)size_value(f.size);
    } else if ([a isEqual:@"AXMinimized"]) {
        id state = w[@"state"];
        id m = w[@"minimized"] ?: ([state isKindOfClass:[NSDictionary class]] ? state[@"minimized"] : nil);
        *out = ax_bool([m boolValue]);
    } else if ([a isEqual:@"AXFullScreen"])
        *out = ax_bool([w[@"fullscreen"] boolValue]);
    else if ([a isEqual:@"AXMain"] || [a isEqual:@"AXFocused"])
        *out = ax_bool(focused_view() == e->view);
    else if ([a isEqual:@"AXParent"]) {
        NSDictionary *pids = window_pids();
        *out = [application_of(w, pids) retain];
    } else
        return kAXErrorAttributeUnsupported;
    return kAXErrorSuccess;
}

static AXError application_attribute(AAXElement *e, NSString *a, id *out)
{
    if ([a isEqual:@"AXRole"]) {
        *out = [@"AXApplication" retain];
        return kAXErrorSuccess;
    }
    if ([a isEqual:@"AXHidden"]) {
        *out = ax_bool(NO);
        return kAXErrorSuccess;
    }
    NSArray *windows = wayfire_windows();
    if (!windows)
        return kAXErrorCannotComplete;
    NSArray *mine = windows_of(e, windows);
    if ([a isEqual:@"AXTitle"]) {
        NSString *title = e->pid == getpid() ? app_name() : e->appID ?: [mine firstObject][@"app-id"];
        *out = [([title isKindOfClass:[NSString class]] ? title : @"") retain];
    } else if ([a isEqual:@"AXWindows"]) {
        NSMutableArray *list = [NSMutableArray array];
        for (NSDictionary *v in mine)
            [list addObject:[new_element(AX_WINDOW, e->pid, e->appID, [v[@"id"] longLongValue]) autorelease]];
        *out = [list copy];
    } else if ([a isEqual:@"AXFocusedWindow"] || [a isEqual:@"AXMainWindow"]) {
        /* the most recently focused of the app's windows */
        NSDictionary *w = [mine firstObject];
        if (!w)
            return kAXErrorNoValue;
        *out = new_element(AX_WINDOW, e->pid, e->appID, [w[@"id"] longLongValue]);
    } else if ([a isEqual:@"AXFrontmost"]) {
        int64_t f = focused_view();
        BOOL front = NO;
        for (NSDictionary *v in mine)
            front |= [v[@"id"] longLongValue] == f;
        *out = ax_bool(front);
    } else
        return kAXErrorAttributeUnsupported;
    return kAXErrorSuccess;
}

static AXError system_wide_attribute(AAXElement *e, NSString *a, id *out)
{
    if ([a isEqual:@"AXRole"]) {
        *out = [@"AXSystemWide" retain];
        return kAXErrorSuccess;
    }
    if (![a isEqual:@"AXFocusedApplication"] && ![a isEqual:@"AXFocusedUIElement"])
        return kAXErrorAttributeUnsupported;
    NSArray *windows = wayfire_windows();
    if (!windows)
        return kAXErrorCannotComplete;
    int64_t f = focused_view();
    NSDictionary *w = f ? window_by_id(windows, f) : nil;
    if (!w)
        return kAXErrorNoValue;
    AAXElement *app = application_of(w, window_pids());
    if ([a isEqual:@"AXFocusedApplication"])
        *out = [app retain];
    else
        *out = new_element(AX_WINDOW, app->pid, app->appID, f);
    return kAXErrorSuccess;
}

AXError AXUIElementCopyAttributeValue(AXUIElementRef element, CFStringRef attribute, CFTypeRef *value)
{
    if (value)
        *value = NULL;
    AXError r = usable(element);
    if (r)
        return r;
    if (!attribute || !value)
        return kAXErrorIllegalArgument;
    AAXElement *e = (AAXElement *)element;
    NSString *a = (NSString *)attribute;
    id out = nil;
    @autoreleasepool {
        r = e->kind == AX_WINDOW        ? window_attribute(e, a, &out)
            : e->kind == AX_APPLICATION ? application_attribute(e, a, &out)
                                        : system_wide_attribute(e, a, &out);
    }
    if (r == kAXErrorSuccess && (out == (id)kCFBooleanTrue || out == (id)kCFBooleanFalse))
        out = copy_value(out);
    *value = (CFTypeRef)out;
    return r;
}

AXError AXUIElementGetAttributeValueCount(AXUIElementRef element, CFStringRef attribute, CFIndex *count)
{
    CFTypeRef value = NULL;
    AXError r = AXUIElementCopyAttributeValue(element, attribute, &value);
    if (r)
        return r;
    if (count)
        *count = [(id)value isKindOfClass:[NSArray class]] ? (CFIndex)[(NSArray *)value count] : 1;
    CFRelease(value);
    return kAXErrorSuccess;
}

AXError AXUIElementCopyAttributeValues(AXUIElementRef element, CFStringRef attribute, CFIndex index,
                                       CFIndex maxValues, CFArrayRef *values)
{
    if (values)
        *values = NULL;
    CFTypeRef value = NULL;
    AXError r = AXUIElementCopyAttributeValue(element, attribute, &value);
    if (r)
        return r;
    if (![(id)value isKindOfClass:[NSArray class]]) {
        CFRelease(value);
        return kAXErrorIllegalArgument;
    }
    NSArray *all = (NSArray *)value;
    NSUInteger from = index < 0 ? 0 : MIN((NSUInteger)index, [all count]);
    NSUInteger n = maxValues < 0 ? 0 : MIN((NSUInteger)maxValues, [all count] - from);
    if (values)
        *values = (CFArrayRef)[[all subarrayWithRange:NSMakeRange(from, n)] copy];
    CFRelease(value);
    return kAXErrorSuccess;
}

static BOOL settable(AAXElement *e, NSString *a)
{
    if (e->kind == AX_WINDOW)
        return [@[ @"AXPosition", @"AXSize", @"AXMinimized", @"AXFullScreen", @"AXMain", @"AXFocused" ]
            containsObject:a];
    return e->kind == AX_APPLICATION && [a isEqual:@"AXFrontmost"];
}

AXError AXUIElementIsAttributeSettable(AXUIElementRef element, CFStringRef attribute, Boolean *result)
{
    if (result)
        *result = false;
    AXError r = usable(element);
    if (r)
        return r;
    if (!attribute || !result)
        return kAXErrorIllegalArgument;
    if (![names_for((AAXElement *)element) containsObject:(NSString *)attribute])
        return kAXErrorAttributeUnsupported;
    *result = settable((AAXElement *)element, (NSString *)attribute);
    return kAXErrorSuccess;
}

static AXError focus(int64_t view)
{
    id reply = AWayfireCall(@"window-rules/focus-view", @{@"id" : @(view)});
    return !reply ? kAXErrorCannotComplete : AWayfireError(reply) ? kAXErrorInvalidUIElement : kAXErrorSuccess;
}

static AXError set_window_attribute(AAXElement *e, NSString *a, id value)
{
    NSArray *windows = wayfire_windows();
    if (!windows)
        return kAXErrorCannotComplete;
    NSDictionary *w = window_by_id(windows, e->view);
    if (!w)
        return kAXErrorInvalidUIElement;
    if ([a isEqual:@"AXPosition"] || [a isEqual:@"AXSize"]) {
        NSArray *outputs = AWayfireOutputs();
        if (!outputs)
            return kAXErrorCannotComplete;
        NSRect f = ax_frame(w, outputs);
        CGPoint p;
        CGSize s;
        if ([a isEqual:@"AXPosition"] && AXValueGetValue((AXValueRef)value, kAXValueTypeCGPoint, &p))
            f.origin = p;
        else if ([a isEqual:@"AXSize"] && AXValueGetValue((AXValueRef)value, kAXValueTypeCGSize, &s))
            f.size = s;
        else
            return kAXErrorIllegalArgument;
        return put_window(w, outputs, f);
    }
    if (![value respondsToSelector:@selector(boolValue)])
        return kAXErrorIllegalArgument;
    BOOL on = [value boolValue];
    id reply;
    if ([a isEqual:@"AXMinimized"])
        reply = AWayfireCall(@"wm-actions/set-minimized", @{@"view_id" : @(e->view), @"state" : @(on)});
    else if ([a isEqual:@"AXFullScreen"])
        reply = AWayfireCall(@"wm-actions/set-fullscreen", @{@"view_id" : @(e->view), @"state" : @(on)});
    else if ([a isEqual:@"AXMain"] || [a isEqual:@"AXFocused"])
        return on ? focus(e->view) : kAXErrorSuccess;
    else
        return kAXErrorAttributeUnsupported;
    return !reply ? kAXErrorCannotComplete : AWayfireError(reply) ? kAXErrorCannotComplete : kAXErrorSuccess;
}

AXError AXUIElementSetAttributeValue(AXUIElementRef element, CFStringRef attribute, CFTypeRef value)
{
    AXError r = usable(element);
    if (r)
        return r;
    if (!attribute || !value)
        return kAXErrorIllegalArgument;
    AAXElement *e = (AAXElement *)element;
    NSString *a = (NSString *)attribute;
    @autoreleasepool {
        if (e->kind == AX_WINDOW)
            return set_window_attribute(e, a, (id)value);
        if (e->kind == AX_APPLICATION && [a isEqual:@"AXFrontmost"]) {
            if (![(id)value boolValue])
                return kAXErrorSuccess;
            NSArray *windows = wayfire_windows();
            NSDictionary *w = [windows_of(e, windows) firstObject];
            return !windows ? kAXErrorCannotComplete : w ? focus([w[@"id"] longLongValue]) : kAXErrorNoValue;
        }
        return [names_for(e) containsObject:a] ? kAXErrorIllegalArgument : kAXErrorAttributeUnsupported;
    }
}

AXError AXUIElementCopyActionNames(AXUIElementRef element, CFArrayRef *names)
{
    AXError r = usable(element);
    if (r)
        return r;
    if (names)
        *names = (CFArrayRef)[(((AAXElement *)element)->kind == AX_WINDOW ? @[ @"AXRaise" ] : @[]) copy];
    return kAXErrorSuccess;
}

AXError AXUIElementPerformAction(AXUIElementRef element, CFStringRef action)
{
    AXError r = usable(element);
    if (r)
        return r;
    AAXElement *e = (AAXElement *)element;
    if (e->kind != AX_WINDOW || ![(NSString *)action isEqual:@"AXRaise"])
        return kAXErrorActionUnsupported;
    return focus(e->view);
}

AXError AXUIElementGetPid(AXUIElementRef element, pid_t *pid)
{
    if (!element || ![(id)element isKindOfClass:[AAXElement class]] || !pid)
        return kAXErrorIllegalArgument;
    AAXElement *e = (AAXElement *)element;
    if (e->kind == AX_SYSTEM_WIDE)
        return kAXErrorIllegalArgument;
    pid_t found = e->pid;
    if (!found && e->kind == AX_WINDOW && AWayfireAvailable())
        found = [window_pids()[@(e->view)] intValue];
    if (!found)
        return kAXErrorCannotComplete;
    *pid = found;
    return kAXErrorSuccess;
}

AXError AXUIElementSetMessagingTimeout(AXUIElementRef element, float timeout)
{
    return element && timeout >= 0 ? kAXErrorSuccess : kAXErrorIllegalArgument;
}

/* Ferry doesn't look inside other apps' windows, so there is no element at
 * a point to give. */
AXError AXUIElementCopyElementAtPosition(AXUIElementRef application, float x, float y, AXUIElementRef *element)
{
    if (element)
        *element = NULL;
    AXError r = usable(application);
    return r ? r : kAXErrorNoValue;
}

/* The keys these calls take, defined where the calls are (a program that
 * checks for a call before using it weak-links its key too). */
const CFStringRef kAXTrustedCheckOptionPrompt = (CFStringRef)@"AXTrustedCheckOptionPrompt";
const CFStringRef kTISPropertyUnicodeKeyLayoutData = (CFStringRef)@"TISPropertyUnicodeKeyLayoutData";
const CFStringRef kTISPropertyInputSourceID = (CFStringRef)@"TISPropertyInputSourceID";
const CFStringRef kTISPropertyLocalizedName = (CFStringRef)@"TISPropertyLocalizedName";
const CFStringRef kTISNotifySelectedKeyboardInputSourceChanged =
    (CFStringRef)@"TISNotifySelectedKeyboardInputSourceChanged";
const CFStringRef kTISNotifyEnabledKeyboardInputSourcesChanged =
    (CFStringRef)@"TISNotifyEnabledKeyboardInputSourcesChanged";
const CFStringRef kTISPropertyInputSourceType = (CFStringRef)@"TISPropertyInputSourceType";
const CFStringRef kTISPropertyInputSourceCategory = (CFStringRef)@"TISPropertyInputSourceCategory";
const CFStringRef kTISPropertyInputSourceLanguages = (CFStringRef)@"TISPropertyInputSourceLanguages";
const CFStringRef kTISPropertyInputSourceIsASCIICapable = (CFStringRef)@"TISPropertyInputSourceIsASCIICapable";
const CFStringRef kTISPropertyInputSourceIsEnabled = (CFStringRef)@"TISPropertyInputSourceIsEnabled";
const CFStringRef kTISPropertyInputSourceIsSelected = (CFStringRef)@"TISPropertyInputSourceIsSelected";
const CFStringRef kTISPropertyInputSourceIsSelectCapable = (CFStringRef)@"TISPropertyInputSourceIsSelectCapable";
const CFStringRef kTISPropertyBundleID = (CFStringRef)@"TISPropertyBundleID";
const CFStringRef kTISCategoryKeyboardInputSource = (CFStringRef)@"TISCategoryKeyboardInputSource";
const CFStringRef kTISTypeKeyboardLayout = (CFStringRef)@"TISTypeKeyboardLayout";
const CFStringRef kHISymbolicHotKeyCode = (CFStringRef)@"kHISymbolicHotKeyCode";
const CFStringRef kHISymbolicHotKeyModifiers = (CFStringRef)@"kHISymbolicHotKeyModifiers";
const CFStringRef kHISymbolicHotKeyEnabled = (CFStringRef)@"kHISymbolicHotKeyEnabled";

/* ---- a Carbon event as an NSEvent (freemac 1.225, Ferry 0.49.0) ----------------------- */

/* A hot key's event is a key down of the hot key's key and modifiers, at
 * the moment it came; any other Carbon event has no NSEvent. */
@implementation NSEvent (FerryCarbonEvents)
static char carbon_ref_key;
+ (NSEvent *)eventWithEventRef:(const void *)ref
{
    ACarbonEvent *event = (ACarbonEvent *)ref;
    if (!event || ![(id)event isKindOfClass:[ACarbonEvent class]] || event->cls != kEventClassKeyboard)
        return nil;
    for (ACarbonHotKey *hk in [hotkeys allValues]) {
        if (hk->hotKeyID.signature != event->hotKey.signature || hk->hotKeyID.id != event->hotKey.id)
            continue;
        NSString *chars = characters_for(hk->keyCode);
        NSEventType type = event->kind == kEventHotKeyReleased ? NSEventTypeKeyUp : NSEventTypeKeyDown;
        NSEvent *e = [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags_for(hk->modifiers)
                                     timestamp:event->time windowNumber:0 context:nil characters:chars
                   charactersIgnoringModifiers:chars isARepeat:NO keyCode:(unsigned short)hk->keyCode];
        objc_setAssociatedObject(e, &carbon_ref_key, event, OBJC_ASSOCIATION_RETAIN);
        return e;
    }
    return nil;
}
- (const void *)eventRef { return objc_getAssociatedObject(self, &carbon_ref_key); }
@end
