/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Itsycal and Gas Mask need of Ferry (freemac 1.232, Ferry 0.56.0),
 * with no display: Auto Layout growing a window past a label that hugs its
 * text at priority 1, a safe-area guide following a view's insets, a view
 * controller's preferred content size, the predicate editor's templates and
 * rows, built in code and from a nib ferry-ibtool compiled
 * (predicate_editor.xib), a few older cell and field calls, the application's will-become and
 * will-resign notifications, Core Audio's objects through AudioToolbox with
 * no sound server, and a few newer Foundation names; and (freemac 1.236)
 * a grid view leaving hidden a view the app hid, as Itsycal's agenda hides
 * its video button, while hiding and showing the views of a row it hides. */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <stdlib.h>

@interface Natural : NSView
@property NSSize natural;
@end
@implementation Natural
- (NSSize)intrinsicContentSize { return self.natural; }
@end

static void show(const char *what, NSRect f)
{
    printf("%s: %.1f,%.1f %.1fx%.1f\n", what, f.origin.x, f.origin.y, f.size.width, f.size.height);
}

static Natural *natural(NSView *superview, CGFloat w, CGFloat h)
{
    Natural *v = [Natural new];
    v.natural = NSMakeSize(w, h);
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [v setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [v setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
    [superview addSubview:v];
    return v;
}

static void layout(void)
{
    /* a borderless window made at zero size, a content view with insets at
     * the top and bottom, a view pinned to its safe area holding a month
     * title that gives way (priority 1) above a grid that doesn't */
    NSWindow *w = [[NSPanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskNonactivatingPanel
                                               backing:NSBackingStoreBuffered defer:NO];
    NSView *content = [NSView new];
    content.additionalSafeAreaInsets = NSEdgeInsetsMake(13, 0, 6, 0);
    w.contentView = content;
    NSView *v = [NSView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:v];
    NSLayoutGuide *safe = content.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [v.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [v.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [v.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];
    NSTextField *title = [NSTextField labelWithString:@"November 2026"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [title setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [title setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [title setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
    [v addSubview:title];
    Natural *grid = natural(v, 173, 150);
    NSDictionary *views = NSDictionaryOfVariableBindings(title, grid);
    for (NSString *f in @[@"H:|-8-[title]-4-|", @"H:|-2-[grid]-2-|", @"V:|[title]-7-[grid]-5-|"])
        [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:f options:0 metrics:nil views:views]];
    [w layoutIfNeeded];
    printf("window content: %.0fx%.0f\n", content.frame.size.width, content.frame.size.height);
    show("pinned to the safe area", v.frame);
    show("grid", grid.frame);
    printf("title as wide as the window allows: %s\n", title.frame.size.width == content.frame.size.width - 12 ? "yes" : "no");

    /* new insets move the guide */
    content.additionalSafeAreaInsets = NSEdgeInsetsMake(20, 0, 10, 0);
    [w layoutIfNeeded];
    show("after new insets", v.frame);
    NSEdgeInsets i = content.safeAreaInsets;
    printf("safeAreaInsets: %.0f %.0f %.0f %.0f\n", i.top, i.left, i.bottom, i.right);

    /* a view controller's preferred size, as Itsycal's agenda sets it */
    NSViewController *vc = [NSViewController new];
    NSView *agenda = [NSView new];
    agenda.translatesAutoresizingMaskIntoConstraints = NO;
    vc.view = agenda;
    [v addSubview:agenda];
    [v removeConstraints:v.constraints];
    views = NSDictionaryOfVariableBindings(title, grid, agenda);
    for (NSString *f in @[@"H:|-8-[title]-4-|", @"H:|-2-[grid]-2-|", @"H:|[agenda]|",
                          @"V:|[title]-7-[grid]-5-[agenda]|"])
        [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:f options:0 metrics:nil views:views]];
    [w layoutIfNeeded];
    printf("no preferred size: agenda %.0f high, window %.0f\n", agenda.frame.size.height, content.frame.size.height);
    vc.preferredContentSize = NSMakeSize(0, 80);
    [w layoutIfNeeded];
    printf("preferred 80: agenda %.0f high, window %.0f\n", agenda.frame.size.height, content.frame.size.height);
    vc.preferredContentSize = NSMakeSize(0, 0.001);
    [w layoutIfNeeded];
    printf("preferred nearly 0: agenda %.0f high, window %.0f\n", agenda.frame.size.height, content.frame.size.height);
    printf("width unchanged: %s\n", content.frame.size.width == 177 ? "yes" : "no");
}

static void predicate_editor(void)
{
    NSArray *left = @[[NSExpression expressionForKeyPath:@"name"], [NSExpression expressionForKeyPath:@"host"]];
    NSPredicateEditorRowTemplate *text = [[NSPredicateEditorRowTemplate alloc]
        initWithLeftExpressions:left rightExpressionAttributeType:700 /* a string */
                       modifier:NSDirectPredicateModifier
                      operators:@[@(NSContainsPredicateOperatorType), @(NSEqualToPredicateOperatorType)]
                        options:NSCaseInsensitivePredicateOption];
    NSPredicateEditorRowTemplate *compound = [[NSPredicateEditorRowTemplate alloc]
        initWithCompoundTypes:@[@(NSAndPredicateType), @(NSOrPredicateType)]];
    printf("template: %lu left, %lu operators, type %lu, options %lu, %lu views\n",
           (unsigned long)text.leftExpressions.count, (unsigned long)text.operators.count,
           (unsigned long)text.rightExpressionAttributeType, (unsigned long)text.options,
           (unsigned long)text.templateViews.count);
    NSPredicate *p = [NSPredicate predicateWithFormat:@"host CONTAINS[c] 'example'"];
    NSPredicate *q = [NSPredicate predicateWithFormat:@"name == 'mail'"];
    NSPredicate *r = [NSPredicate predicateWithFormat:@"size > 3"];
    printf("matches: text %s %s %s, compound %s\n", [text matchForPredicate:p] > 0 ? "yes" : "no",
           [text matchForPredicate:q] > 0 ? "yes" : "no", [text matchForPredicate:r] > 0 ? "yes" : "no",
           [compound matchForPredicate:[NSCompoundPredicate orPredicateWithSubpredicates:@[p, q]]] > 0 ? "yes" : "no");
    [text setPredicate:p];
    printf("shown back: %s\n", [[text predicateWithSubpredicates:nil] predicateFormat].UTF8String);
    NSPredicateEditorRowTemplate *copied = [text copy];
    printf("copy keeps its operators: %s\n", [copied.operators isEqual:text.operators] ? "yes" : "no");

    NSPredicateEditor *editor = [[NSPredicateEditor alloc] initWithFrame:NSMakeRect(0, 0, 500, 200)];
    editor.rowTemplates = @[compound, text];
    NSPredicate *both = [NSCompoundPredicate orPredicateWithSubpredicates:@[p, q]];
    editor.objectValue = both;
    printf("rows: %ld\n", (long)editor.numberOfRows);
    printf("predicate: %s\n", [editor.predicate predicateFormat].UTF8String);
}

@interface PEOwner : NSObject
@property (strong) IBOutlet NSPredicateEditor *editor;
@end
@implementation PEOwner
@end

static void predicate_editor_nib(void)
{
    NSString *path = [NSString stringWithFormat:@"%s/Predicates.nib", getenv("FERRY_TEST_DATA")];
    NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
    PEOwner *owner = [PEOwner new];
    NSArray *top = nil;
    printf("nib instantiated: %s\n", [nib instantiateWithOwner:owner topLevelObjects:&top] ? "yes" : "no");
    NSPredicateEditor *e = owner.editor;
    printf("from the nib: %s, %lu templates\n", e.className.UTF8String, (unsigned long)e.rowTemplates.count);
    for (NSPredicateEditorRowTemplate *t in e.rowTemplates) {
        NSMutableArray *titles = [NSMutableArray array];
        for (NSView *v in t.templateViews)
            if ([v isKindOfClass:[NSPopUpButton class]])
                [titles addObject:[[(NSPopUpButton *)v itemTitles] componentsJoinedByString:@"/"]];
        printf("  %s: %s\n", t.compoundTypes.count ? "compound" : "simple",
               [titles componentsJoinedByString:@" | "].UTF8String);
    }
    e.objectValue = [NSPredicate predicateWithFormat:@"name BEGINSWITH[c] 'local' OR contents CONTAINS[c] '127.0.0.1'"];
    printf("rows: %ld\n", (long)e.numberOfRows);
    printf("predicate: %s\n", [e.predicate predicateFormat].UTF8String);
}

@interface Watcher : NSObject
@end
@implementation Watcher
- (void)note:(NSNotification *)n { printf("notification: %s\n", n.name.UTF8String); }
@end

static void older_calls(void)
{
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 22)];
    [f setTitleWithMnemonic:@"&Hosts"];
    printf("setTitleWithMnemonic: %s\n", f.stringValue.UTF8String);
    NSButtonCell *cell = [[NSButtonCell alloc] initTextCell:@"x"];
    printf("button cell background: %s\n", cell.backgroundColor ? "set" : "none");
    cell.backgroundColor = [NSColor redColor];
    printf("button cell background: %s\n", [cell.backgroundColor isEqual:[NSColor redColor]] ? "red" : "other");
    NSRect mask = [cell focusRingMaskBoundsForFrame:NSMakeRect(0, 0, 40, 20) inView:nil];
    show("focus ring mask bounds", mask);

    Watcher *w = [Watcher new];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for (NSString *name in @[NSApplicationWillBecomeActiveNotification, NSApplicationDidBecomeActiveNotification,
                             NSApplicationWillResignActiveNotification, NSApplicationDidResignActiveNotification])
        [nc addObserver:w selector:@selector(note:) name:name object:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp deactivate];
    [nc removeObserver:w];
}

static void core_audio(void)
{
    /* no sound server, whatever this system has (freemac 1.234): the
     * default devices are Ferry's null device, which has no volume */
    setenv("FERRY_AUDIO", "null", 1);
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal,
                                    kAudioObjectPropertyElementMain};
    AudioDeviceID dev = 0;
    UInt32 size = sizeof dev;
    OSStatus s = AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &dev);
    printf("default output: status %d, device %s\n", (int)s, dev != kAudioObjectUnknown ? "found" : "none");
    a.mSelector = kAudioDevicePropertyVolumeScalar;
    a.mScope = kAudioObjectPropertyScopeOutput;
    Float32 volume = -1;
    size = sizeof volume;
    s = AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, &volume);
    printf("volume with no sound server: %s\n", s == kAudioHardwareUnknownPropertyError && !AudioObjectHasProperty(dev, &a)
                                                     ? "no volume control"
                                                     : "answered");
    printf("an unknown object: %s\n", AudioObjectHasProperty(99, &a) ? "has it" : "hasn't");
}

static void foundation(void)
{
    printf("localizedStandardCompare: %ld %ld\n", (long)[@"File 9" localizedStandardCompare:@"file 10"],
           (long)[@"b" localizedStandardCompare:@"A"]);
    printf("NSURLTagNamesKey: %s\n", NSURLTagNamesKey.UTF8String);
    printf("resourceSpecifier: %s\n", [NSURL URLWithString:@"mailto:someone@example.com"].resourceSpecifier.UTF8String);
    printf("kSCNetworkFlagsReachable: %s\n", kSCNetworkFlagsReachable == kSCNetworkReachabilityFlagsReachable ? "same" : "differs");
    CALayer *l = [CALayer layer];
    printf("cornerCurve: %s\n", l.cornerCurve.UTF8String);
    l.cornerCurve = kCACornerCurveContinuous;
    printf("cornerCurve: %s\n", l.cornerCurve.UTF8String);
}

/* Itsycal's agenda cell: a grid of a label and a button the app hides
 * when the event has no meeting link */
static void grid_hidden(void)
{
    NSTextField *label = [NSTextField labelWithString:@"9:30 AM - 10 AM"];
    NSButton *video = [NSButton buttonWithTitle:@"V" target:nil action:NULL];
    NSGridView *grid = [NSGridView gridViewWithViews:@[ @[ label, video ] ]];
    video.hidden = YES;
    [grid setFrame:NSMakeRect(0, 0, 200, 30)];
    [grid layoutSubtreeIfNeeded];
    printf("a grid's button the app hid: hidden %d\n", video.hidden);
    [grid rowAtIndex:0].hidden = YES;
    [grid layoutSubtreeIfNeeded];
    printf("  its row hidden: label hidden %d, button hidden %d\n", label.hidden, video.hidden);
    [grid rowAtIndex:0].hidden = NO;
    [grid layoutSubtreeIfNeeded];
    printf("  its row shown again: label hidden %d, button hidden %d\n", label.hidden, video.hidden);
    video.hidden = NO;
    [grid layoutSubtreeIfNeeded];
    printf("  shown by the app: button hidden %d\n", video.hidden);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        layout();
        predicate_editor();
        predicate_editor_nib();
        older_calls();
        core_audio();
        foundation();
        grid_hidden();
    }
    return 0;
}
