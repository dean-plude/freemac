/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: events and the responder chain. GTK's input arrives here
 * (see NSApplication.m) and becomes NSEvents with a Mac's key codes,
 * characters and modifier flags; NSResponder passes what a view doesn't
 * handle up the chain, and turns key presses into the text-editing
 * commands (insertText:, deleteBackward:, moveLeft: ...) Apple documents
 * for interpretKeyEvents:. */
#import "AInternal.h"

/* ---- NSEvent ------------------------------------------------------------------------ */

@implementation NSEvent {
@public
    NSEventType _type;
    NSEventModifierFlags _flags;
    NSTimeInterval _time;
    NSWindow *_window;          /* not retained, as on a Mac */
    NSInteger _windowNumber;
    NSPoint _location;
    NSInteger _clicks, _button, _number;
    float _pressure;
    CGFloat _dx, _dy;
    BOOL _precise, _repeat;
    NSString *_chars, *_unmodified;
    unsigned short _keyCode;
    short _subtype;
    NSInteger _data1, _data2;
    NSInteger _trackingNumber;  /* entered, exited and cursor-update events (NSTrackingArea.m) */
    void *_userData;
    NSTrackingArea *_trackingArea;
}

static NSPoint mouse_location;
static NSUInteger mouse_buttons;
static NSEventModifierFlags current_flags;
static NSInteger event_number;

static NSTimeInterval now(void) { return [[NSProcessInfo processInfo] systemUptime]; }

static NSEvent *new_event(NSEventType type, NSPoint location, NSEventModifierFlags flags, NSTimeInterval time,
                          NSInteger windowNumber)
{
    NSEvent *e = [[[NSEvent alloc] init] autorelease];
    e->_type = type;
    e->_location = location;
    e->_flags = flags;
    e->_time = time > 0 ? time : now();
    e->_windowNumber = windowNumber;
    e->_window = windowNumber ? [NSApp windowWithWindowNumber:windowNumber] : nil;
    e->_number = ++event_number;
    return e;
}

+ (NSEvent *)mouseEventWithType:(NSEventType)type location:(NSPoint)location
                  modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                   windowNumber:(NSInteger)windowNumber context:(id)context eventNumber:(NSInteger)eventNumber
                     clickCount:(NSInteger)clickCount pressure:(float)pressure
{
    NSEvent *e = new_event(type, location, flags, time, windowNumber);
    e->_clicks = clickCount;
    e->_pressure = pressure;
    e->_button = type == NSEventTypeRightMouseDown || type == NSEventTypeRightMouseUp ||
                         type == NSEventTypeRightMouseDragged
                     ? 1
                 : type == NSEventTypeOtherMouseDown || type == NSEventTypeOtherMouseUp ||
                         type == NSEventTypeOtherMouseDragged
                     ? 2
                     : 0;
    return e;
}

+ (NSEvent *)keyEventWithType:(NSEventType)type location:(NSPoint)location
                modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                 windowNumber:(NSInteger)windowNumber context:(id)context characters:(NSString *)characters
  charactersIgnoringModifiers:(NSString *)unmodCharacters isARepeat:(BOOL)repeat keyCode:(unsigned short)code
{
    NSEvent *e = new_event(type, location, flags, time, windowNumber);
    e->_chars = [characters copy];
    e->_unmodified = [unmodCharacters copy];
    e->_repeat = repeat;
    e->_keyCode = code;
    return e;
}

+ (NSEvent *)otherEventWithType:(NSEventType)type location:(NSPoint)location
                  modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                   windowNumber:(NSInteger)windowNumber context:(id)context subtype:(short)subtype
                          data1:(NSInteger)d1 data2:(NSInteger)d2
{
    NSEvent *e = new_event(type, location, flags, time, windowNumber);
    e->_subtype = subtype;
    e->_data1 = d1;
    e->_data2 = d2;
    return e;
}

+ (NSPoint)mouseLocation { return mouse_location; }
+ (NSEventModifierFlags)modifierFlags { return current_flags; }
+ (NSUInteger)pressedMouseButtons { return mouse_buttons; }
+ (NSTimeInterval)doubleClickInterval { return 0.5; }

- (void)dealloc
{
    [_chars release];
    [_unmodified release];
    [_trackingArea release];
    [super dealloc];
}

+ (NSEvent *)enterExitEventWithType:(NSEventType)type location:(NSPoint)location
                      modifierFlags:(NSEventModifierFlags)flags timestamp:(NSTimeInterval)time
                       windowNumber:(NSInteger)windowNumber context:(id)context eventNumber:(NSInteger)eventNumber
                     trackingNumber:(NSInteger)trackingNumber userData:(void *)userData
{
    NSEvent *e = new_event(type, location, flags, time, windowNumber);
    e->_trackingNumber = trackingNumber;
    e->_userData = userData;
    return e;
}
- (NSInteger)trackingNumber { return _trackingNumber; }
- (void *)userData { return _userData; }
- (NSTrackingArea *)trackingArea { return _trackingArea; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

- (NSEventType)type { return _type; }
- (NSEventModifierFlags)modifierFlags { return _flags; }
- (NSTimeInterval)timestamp { return _time; }
- (NSWindow *)window { return _window; }
- (NSInteger)windowNumber { return _windowNumber; }
- (NSPoint)locationInWindow { return _location; }
- (NSInteger)clickCount { return _clicks; }
- (NSInteger)buttonNumber { return _button; }
- (NSInteger)eventNumber { return _number; }
- (float)pressure { return _pressure; }
- (CGFloat)deltaX { return _dx; }
- (CGFloat)deltaY { return _dy; }
- (CGFloat)deltaZ { return 0; }
- (CGFloat)scrollingDeltaX { return _precise ? _dx : _dx; }
- (CGFloat)scrollingDeltaY { return _precise ? _dy : _dy; }
- (BOOL)hasPreciseScrollingDeltas { return _precise; }
- (NSString *)characters { return _chars; }
- (NSString *)charactersIgnoringModifiers { return _unmodified; }
- (BOOL)isARepeat { return _repeat; }
- (unsigned short)keyCode { return _keyCode; }
- (short)subtype { return _subtype; }
- (NSInteger)data1 { return _data1; }
- (NSInteger)data2 { return _data2; }

- (NSString *)description
{
    static const char *names[] = {
        [1] = "LMouseDown", [2] = "LMouseUp", [3] = "RMouseDown", [4] = "RMouseUp", [5] = "MouseMoved",
        [6] = "LMouseDragged", [7] = "RMouseDragged", [8] = "MouseEntered", [9] = "MouseExited",
        [10] = "KeyDown", [11] = "KeyUp", [12] = "FlagsChanged", [15] = "ApplicationDefined",
        [22] = "ScrollWheel", [25] = "OtherMouseDown", [26] = "OtherMouseUp", [27] = "OtherMouseDragged",
    };
    const char *name = _type < sizeof names / sizeof names[0] && names[_type] ? names[_type] : "?";
    if (_type == NSEventTypeKeyDown || _type == NSEventTypeKeyUp)
        return [NSString stringWithFormat:@"NSEvent: type=%s loc=(%g,%g) flags=0x%lx win=%ld chars=\"%@\" "
                                          @"unmodchars=\"%@\" repeat=%d keyCode=%u",
                                          name, _location.x, _location.y, (unsigned long)_flags, (long)_windowNumber,
                                          _chars, _unmodified, _repeat, _keyCode];
    return [NSString stringWithFormat:@"NSEvent: type=%s loc=(%g,%g) flags=0x%lx win=%ld clickCount=%ld", name,
                                      _location.x, _location.y, (unsigned long)_flags, (long)_windowNumber,
                                      (long)_clicks];
}
@end

NSEvent *AMouseEvent(NSEventType type, NSPoint location, NSEventModifierFlags flags, NSWindow *window,
                     NSInteger clicks, NSInteger button)
{
    NSEvent *e = [NSEvent mouseEventWithType:type location:location modifierFlags:flags timestamp:0
                                windowNumber:[window windowNumber] context:nil eventNumber:0
                                  clickCount:clicks pressure:clicks ? 1 : 0];
    e->_button = button;
    e->_window = window;
    return e;
}

NSEvent *AKeyEvent(NSEventType type, NSEventModifierFlags flags, NSWindow *window, NSString *chars,
                   NSString *unmodified, BOOL repeat, unsigned short code)
{
    NSEvent *e = [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:0
                              windowNumber:[window windowNumber] context:nil characters:chars
               charactersIgnoringModifiers:unmodified isARepeat:repeat keyCode:code];
    e->_window = window;
    return e;
}

NSEvent *AScrollEvent(NSPoint location, NSEventModifierFlags flags, NSWindow *window, CGFloat dx, CGFloat dy,
                      BOOL precise)
{
    NSEvent *e = new_event(NSEventTypeScrollWheel, location, flags, 0, [window windowNumber]);
    e->_window = window;
    e->_dx = dx;
    e->_dy = dy;
    e->_precise = precise;
    return e;
}

NSEvent *ATrackingEvent(NSEventType type, NSPoint location, NSEvent *cause, NSWindow *window,
                        NSInteger number, void *userData, NSTrackingArea *area)
{
    NSEvent *e = new_event(type, location, [cause modifierFlags], [cause timestamp], [window windowNumber]);
    e->_window = window;
    e->_trackingNumber = number;
    e->_userData = userData;
    e->_trackingArea = [area retain];
    return e;
}

void AEventSetWindow(NSEvent *event, NSWindow *window)
{
    event->_window = window;
    event->_windowNumber = [window windowNumber];
}

void ASetCurrentModifiers(NSEventModifierFlags flags) { current_flags = flags; }
void ASetMouseLocation(NSPoint p, NSUInteger buttons)
{
    mouse_location = p;
    mouse_buttons = buttons;
}

/* ---- keys -------------------------------------------------------------------------- */

/* On freemac the Command key reaches apps as Ctrl (Strata tells an app Ctrl
 * is held while Command is, so that GTK apps copy and paste with it), so
 * Ctrl is Command here too, as is Super where a desktop passes it through.
 * Alt is Option. Setting FERRY_CONTROL_KEY=control makes Ctrl the Mac's
 * Control key instead, for desktops that don't do this. */
NSEventModifierFlags AModifiersFromGdk(unsigned state)
{
    static int ctrl_is_control = -1;
    if (ctrl_is_control < 0) {
        const char *v = getenv("FERRY_CONTROL_KEY");
        ctrl_is_control = v && !strcmp(v, "control");
    }
    NSEventModifierFlags f = 0;
    if (state & GDK_SHIFT_MASK)
        f |= NSEventModifierFlagShift;
    if (state & GDK_LOCK_MASK)
        f |= NSEventModifierFlagCapsLock;
    if (state & GDK_CONTROL_MASK)
        f |= ctrl_is_control ? NSEventModifierFlagControl : NSEventModifierFlagCommand;
    if (state & GDK_MOD1_MASK)
        f |= NSEventModifierFlagOption;
    if (state & (GDK_SUPER_MASK | GDK_META_MASK))
        f |= NSEventModifierFlagCommand;
    return f;
}

/* Linux key numbers (GDK's hardware key code less 8) to a Mac's virtual key
 * codes, which Mac programs use for keys whatever the layout. */
unsigned short AMacKeyCode(uint16_t hardware)
{
    static const unsigned char mac[128] = {
        [1] = 0x35,                                                         /* Escape */
        [2] = 0x12, [3] = 0x13, [4] = 0x14, [5] = 0x15, [6] = 0x17,         /* 1-5 */
        [7] = 0x16, [8] = 0x1A, [9] = 0x1C, [10] = 0x19, [11] = 0x1D,       /* 6-0 */
        [12] = 0x1B, [13] = 0x18, [14] = 0x33, [15] = 0x30,                 /* - = Backspace Tab */
        [16] = 0x0C, [17] = 0x0D, [18] = 0x0E, [19] = 0x0F, [20] = 0x11,    /* Q W E R T */
        [21] = 0x10, [22] = 0x20, [23] = 0x22, [24] = 0x1F, [25] = 0x23,    /* Y U I O P */
        [26] = 0x21, [27] = 0x1E, [28] = 0x24, [29] = 0x3B,                 /* [ ] Return Ctrl */
        [30] = 0x00, [31] = 0x01, [32] = 0x02, [33] = 0x03, [34] = 0x05,    /* A S D F G */
        [35] = 0x04, [36] = 0x26, [37] = 0x28, [38] = 0x25, [39] = 0x29,    /* H J K L ; */
        [40] = 0x27, [41] = 0x32, [42] = 0x38, [43] = 0x2A,                 /* ' ` Shift \ */
        [44] = 0x06, [45] = 0x07, [46] = 0x08, [47] = 0x09, [48] = 0x0B,    /* Z X C V B */
        [49] = 0x2D, [50] = 0x2E, [51] = 0x2B, [52] = 0x2F, [53] = 0x2C,    /* N M , . / */
        [54] = 0x3C, [55] = 0x43, [56] = 0x3A, [57] = 0x31, [58] = 0x39,    /* RShift KP* Alt Space Caps */
        [59] = 0x7A, [60] = 0x78, [61] = 0x63, [62] = 0x76, [63] = 0x60,    /* F1-F5 */
        [64] = 0x61, [65] = 0x62, [66] = 0x64, [67] = 0x65, [68] = 0x6D,    /* F6-F10 */
        [69] = 0x47, [71] = 0x59, [72] = 0x5B, [73] = 0x5C, [74] = 0x4E,    /* NumLock(Clear) KP7-9 KP- */
        [75] = 0x56, [76] = 0x57, [77] = 0x58, [78] = 0x45,                 /* KP4-6 KP+ */
        [79] = 0x53, [80] = 0x54, [81] = 0x55, [82] = 0x52, [83] = 0x41,    /* KP1-3 KP0 KP. */
        [86] = 0x0A, [87] = 0x67, [88] = 0x6F,                              /* 102nd F11 F12 */
        [96] = 0x4C, [97] = 0x3E, [98] = 0x4B, [100] = 0x3D,                /* KPEnter RCtrl KP/ RAlt */
        [102] = 0x73, [103] = 0x7E, [104] = 0x74, [105] = 0x7B,             /* Home Up PgUp Left */
        [106] = 0x7C, [107] = 0x77, [108] = 0x7D, [109] = 0x79,             /* Right End Down PgDn */
        [110] = 0x72, [111] = 0x75, [117] = 0x51,                           /* Insert(Help) Delete KP= */
        [125] = 0x37, [126] = 0x36,                                         /* Super (Command) */
    };
    unsigned key = hardware >= 8 ? hardware - 8u : 0;
    /* A is 0, so unmapped keys get a code no Mac key uses */
    if (key == 30)
        return 0;
    return key < 128 && mac[key] ? mac[key] : 0xFF;
}

static NSString *one(unichar c) { return [NSString stringWithCharacters:&c length:1]; }

/* The characters a key types, as a Mac gives them: the function-key
 * characters for keys that don't type, and control characters for Return,
 * Tab, Backspace and Escape. */
NSString *ACharactersForKeyval(unsigned keyval, unsigned state, BOOL ignoringModifiers)
{
    switch (keyval) {
    case 0xff0d: return one(NSCarriageReturnCharacter);    /* Return */
    case 0xff8d: return one(NSEnterCharacter);             /* KP_Enter */
    case 0xff08: return one(NSDeleteCharacter);            /* BackSpace */
    case 0xff09: return one(NSTabCharacter);
    case 0xfe20: return one(NSBackTabCharacter);           /* ISO_Left_Tab, Shift-Tab */
    case 0xff1b: return one(0x1b);                         /* Escape */
    case 0xffff: return one(NSDeleteFunctionKey);
    case 0xff50: return one(NSHomeFunctionKey);
    case 0xff51: return one(NSLeftArrowFunctionKey);
    case 0xff52: return one(NSUpArrowFunctionKey);
    case 0xff53: return one(NSRightArrowFunctionKey);
    case 0xff54: return one(NSDownArrowFunctionKey);
    case 0xff55: return one(NSPageUpFunctionKey);
    case 0xff56: return one(NSPageDownFunctionKey);
    case 0xff57: return one(NSEndFunctionKey);
    case 0xff63: return one(NSInsertFunctionKey);
    }
    if (keyval >= 0xffbe && keyval <= 0xffc9)              /* F1-F12 */
        return one((unichar)(NSF1FunctionKey + keyval - 0xffbe));
    if (keyval >= 0xffe1 && keyval <= 0xffee)              /* modifier keys type nothing */
        return @"";
    uint32_t u = gdk_keyval_to_unicode(keyval);
    if (!u)
        return @"";
    /* the Mac's Control key makes control characters from letters */
    if (!ignoringModifiers && (AModifiersFromGdk(state) & NSEventModifierFlagControl) && u < 128 &&
        isalpha((int)u))
        return one((unichar)(tolower((int)u) - 'a' + 1));
    if (u > 0xffff) {
        unichar pair[2] = {(unichar)(0xD800 + ((u - 0x10000) >> 10)), (unichar)(0xDC00 + ((u - 0x10000) & 0x3ff))};
        return [NSString stringWithCharacters:pair length:2];
    }
    return one((unichar)u);
}

/* ---- NSResponder ------------------------------------------------------------------- */

@implementation NSResponder {
    NSResponder *_next;
}
- (NSResponder *)nextResponder { return _next; }
- (void)setNextResponder:(NSResponder *)next { _next = next; }
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)becomeFirstResponder { return YES; }
- (BOOL)resignFirstResponder { return YES; }
#define PASS(sel)                                                                                                \
    -(void)sel : (NSEvent *)event                                                                                \
    {                                                                                                            \
        if (_next)                                                                                               \
            [_next sel:event];                                                                                   \
        else                                                                                                     \
            [self noResponderFor:@selector(sel:)];                                                               \
    }
PASS(mouseDown)
PASS(mouseDragged)
PASS(mouseUp)
PASS(mouseMoved)
PASS(mouseEntered)
PASS(mouseExited)
PASS(rightMouseDown)
PASS(rightMouseDragged)
PASS(rightMouseUp)
PASS(otherMouseDown)
PASS(otherMouseDragged)
PASS(otherMouseUp)
PASS(scrollWheel)
PASS(keyDown)
PASS(keyUp)
PASS(flagsChanged)
#undef PASS
- (BOOL)performKeyEquivalent:(NSEvent *)event { return NO; }
/* A window has one (or its document's); a responder uses its window's. */
- (NSUndoManager *)undoManager { return [_next undoManager]; }

/* A key press that reaches the end of the chain unhandled beeps, as on a
 * Mac; other events are dropped quietly. */
- (void)noResponderFor:(SEL)sel
{
    if (sel == @selector(keyDown:))
        NSBeep();
}

- (BOOL)tryToPerform:(SEL)action with:(id)object
{
    if ([self respondsToSelector:action]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, action, object);
        return YES;
    }
    return [_next tryToPerform:action with:object];
}

- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
    return [_next validRequestorForSendType:sendType returnType:returnType];
}

- (void)insertText:(id)string
{
    if (_next)
        [_next insertText:string];
    else
        NSBeep();
}

- (void)doCommandBySelector:(SEL)selector
{
    if ([self respondsToSelector:selector])
        ((void (*)(id, SEL, id))objc_msgSend)(self, selector, nil);
    else if (_next)
        [_next doCommandBySelector:selector];
    else if (selector != @selector(cancelOperation:) && selector != @selector(noop:))
        NSBeep();
}

/* The standard key bindings: the commands a key press means in a text view,
 * as listed in Apple's documentation of NSStandardKeyBindingResponding. */
static SEL command_for(unichar c, NSEventModifierFlags f)
{
    /* (BOOL is a char: the flags are above its bits) */
    BOOL shift = (f & NSEventModifierFlagShift) != 0, opt = (f & NSEventModifierFlagOption) != 0,
         cmd = (f & NSEventModifierFlagCommand) != 0, ctrl = (f & NSEventModifierFlagControl) != 0;
    switch (c) {
    case NSCarriageReturnCharacter:
    case NSEnterCharacter:
    case NSNewlineCharacter:
        return opt ? @selector(insertNewlineIgnoringFieldEditor:) : @selector(insertNewline:);
    case NSTabCharacter:
        return shift ? @selector(insertBacktab:) : opt ? @selector(insertTabIgnoringFieldEditor:) : @selector(insertTab:);
    case NSBackTabCharacter: return @selector(insertBacktab:);
    case NSDeleteCharacter:
    case NSBackspaceCharacter:
        return cmd ? @selector(deleteToBeginningOfLine:) : opt ? @selector(deleteWordBackward:)
                                                               : @selector(deleteBackward:);
    case NSDeleteFunctionKey:
        return opt ? @selector(deleteWordForward:) : @selector(deleteForward:);
    case 0x1b: return @selector(cancelOperation:);
    case NSLeftArrowFunctionKey:
        if (cmd)
            return shift ? @selector(moveToBeginningOfLineAndModifySelection:) : @selector(moveToBeginningOfLine:);
        if (opt)
            return shift ? @selector(moveWordLeftAndModifySelection:) : @selector(moveWordLeft:);
        return shift ? @selector(moveLeftAndModifySelection:) : @selector(moveLeft:);
    case NSRightArrowFunctionKey:
        if (cmd)
            return shift ? @selector(moveToEndOfLineAndModifySelection:) : @selector(moveToEndOfLine:);
        if (opt)
            return shift ? @selector(moveWordRightAndModifySelection:) : @selector(moveWordRight:);
        return shift ? @selector(moveRightAndModifySelection:) : @selector(moveRight:);
    case NSUpArrowFunctionKey:
        if (cmd)
            return shift ? @selector(moveToBeginningOfDocumentAndModifySelection:) : @selector(moveToBeginningOfDocument:);
        return shift ? @selector(moveUpAndModifySelection:) : @selector(moveUp:);
    case NSDownArrowFunctionKey:
        if (cmd)
            return shift ? @selector(moveToEndOfDocumentAndModifySelection:) : @selector(moveToEndOfDocument:);
        return shift ? @selector(moveDownAndModifySelection:) : @selector(moveDown:);
    case NSHomeFunctionKey:
        return shift ? @selector(moveToBeginningOfLineAndModifySelection:) : @selector(moveToBeginningOfLine:);
    case NSEndFunctionKey:
        return shift ? @selector(moveToEndOfLineAndModifySelection:) : @selector(moveToEndOfLine:);
    case NSPageUpFunctionKey: return @selector(pageUp:);
    case NSPageDownFunctionKey: return @selector(pageDown:);
    }
    if (ctrl) {
        switch (c) {
        case 'a' - 'a' + 1: return @selector(moveToBeginningOfParagraph:);
        case 'e' - 'a' + 1: return @selector(moveToEndOfParagraph:);
        case 'b' - 'a' + 1: return @selector(moveBackward:);
        case 'f' - 'a' + 1: return @selector(moveForward:);
        case 'd' - 'a' + 1: return @selector(deleteForward:);
        case 'h' - 'a' + 1: return @selector(deleteBackward:);
        case 'k' - 'a' + 1: return @selector(deleteToEndOfParagraph:);
        case 'n' - 'a' + 1: return @selector(moveDown:);
        case 'p' - 'a' + 1: return @selector(moveUp:);
        }
        return @selector(noop:);
    }
    return NULL;
}

- (void)interpretKeyEvents:(NSArray<NSEvent *> *)events
{
    for (NSEvent *e in events) {
        if ([e type] != NSEventTypeKeyDown)
            continue;
        NSString *chars = [e characters];
        NSEventModifierFlags f = [e modifierFlags];
        if (![chars length])
            continue;
        SEL sel = [chars length] == 1 ? command_for([chars characterAtIndex:0], f) : NULL;
        if (sel)
            [self doCommandBySelector:sel];
        else if (!(f & NSEventModifierFlagCommand))
            [self insertText:chars];
        else
            [self doCommandBySelector:@selector(noop:)];
    }
}
@end

/* ---- event monitors (freemac 1.215, Ferry 0.41.0) -----------------------------------
 * A local monitor's block sees each event of its kinds that the app sends
 * itself (-[NSApplication sendEvent:]) and returns the event to go on with,
 * another one, or nil to drop it. A global monitor's block sees events sent
 * to other apps; on freemac no app sees another's keys, so the only events a
 * global monitor gets are key-downs for the app's own registered hotkeys
 * (Carbon.m), whichever app is in front. */

@interface AEventMonitor : NSObject {
@public
    NSEventMask mask;
    id block;
    BOOL global;
}
@end
@implementation AEventMonitor
- (void)dealloc
{
    [block release];
    [super dealloc];
}
@end

static NSMutableArray *monitors;

static id add_monitor(NSEventMask mask, id block, BOOL global)
{
    if (!block)
        return nil;
    if (!monitors)
        monitors = [[NSMutableArray alloc] init];
    AEventMonitor *m = [[AEventMonitor alloc] init];
    m->mask = mask;
    m->block = [block copy];
    m->global = global;
    [monitors addObject:m];
    return [m autorelease];
}

@implementation NSEvent (FerryMonitors)
+ (id)addLocalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(NSEvent * (^)(NSEvent *))block
{
    return add_monitor(mask, block, NO);
}
+ (id)addGlobalMonitorForEventsMatchingMask:(NSEventMask)mask handler:(void (^)(NSEvent *))block
{
    return add_monitor(mask, block, YES);
}
+ (void)removeMonitor:(id)monitor
{
    if (monitor)
        [monitors removeObjectIdenticalTo:monitor];
}
@end

NSEvent *ALocalMonitorsFilter(NSEvent *event)
{
    if (![monitors count])
        return event;
    for (AEventMonitor *m in [[monitors copy] autorelease]) {
        if (m->global || !(m->mask & NSEventMaskFromType([event type])) || ![monitors containsObject:m])
            continue;
        event = ((NSEvent * (^)(NSEvent *)) m->block)(event);
        if (!event)
            return nil;
    }
    return event;
}

void AGlobalMonitorsDeliver(NSEvent *event)
{
    for (AEventMonitor *m in [[monitors copy] autorelease])
        if (m->global && (m->mask & NSEventMaskFromType([event type])) && [monitors containsObject:m])
            ((void (^)(NSEvent *))m->block)(event);
}
