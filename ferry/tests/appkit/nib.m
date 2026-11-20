/* Nib loading (M5): an app bundle whose Info.plist names MainMenu as its
 * main nib, started with NSApplicationMain, and a second nib (Panel, in
 * the folder form) loaded by the program. The nibs are made by
 * make_nibs.py in the layout Interface Builder's compiled nibs use. Runs
 * with no display, so windows are drawn off screen. Built with ARC. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>

static const char *str(NSString *s) { return s ? s.UTF8String : "(nil)"; }
static const char *yes(BOOL b) { return b ? "yes" : "no"; }

/* A custom view, made from an NSCustomView with initWithFrame:, with two
 * properties set from the nib's runtime attributes. */
@interface ColorSwatch : NSView
@property (copy) NSString *swatchName;
@property NSInteger corner;
@property BOOL madeWithFrame, awoke;
@end
@implementation ColorSwatch
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        _madeWithFrame = YES;
    return self;
}
- (void)awakeFromNib { _awoke = YES; }
- (void)drawRect:(NSRect)dirty
{
    [[NSColor colorWithSRGBRed:0 green:0.5 blue:0.5 alpha:1] set];
    NSRectFill(self.bounds);
}
@end

/* A button of the app's own class, through NSClassSwapper. */
@interface LoudButton : NSButton
@property BOOL awoke;
@end
@implementation LoudButton
- (void)awakeFromNib { _awoke = YES; }
@end

@interface Helper : NSObject
@property (weak) id owner;
@end
@implementation Helper
- (void)awakeFromNib { printf("Helper awakeFromNib, owner outlet set: %s\n", yes(self.owner != nil)); }
@end

@interface PanelController : NSObject
@property (strong) NSPanel *panel;
@property (strong) NSTextField *note;
@property (strong) Helper *helper;
@end
@implementation PanelController
- (void)awakeFromNib { printf("PanelController awakeFromNib\n"); }
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTextField *nameField, *label;
@property (strong) NSSecureTextField *secureField;
@property (strong) NSButton *greetButton, *loudBox;
@property (strong) ColorSwatch *swatch;
@property (strong) LoudButton *swapped;
@property (strong) NSView *unknownView;
@end

@implementation AppDelegate
- (void)awakeFromNib
{
    printf("AppDelegate awakeFromNib: window %s, field %s, button %s\n", yes(_window != nil), yes(_nameField != nil),
           yes(_greetButton != nil));
}
- (void)greet:(id)sender
{
    printf("greet: from %s, \"Hello, %s%s\"\n", str([sender title]), str(_nameField.stringValue),
           _loudBox.state == NSControlStateValueOn ? "!" : ".");
}
- (void)toggleLoud:(id)sender { printf("toggleLoud: state %ld\n", (long)[sender state]); }
- (void)sayHello:(id)sender { printf("sayHello: from the menu item \"%s\"\n", str([sender title])); }

static void show_menu(NSMenu *menu, int depth)
{
    for (NSMenuItem *item in menu.itemArray) {
        printf("%*s- %s", depth * 2, "", item.isSeparatorItem ? "(separator)" : str(item.title));
        if (item.keyEquivalent.length)
            printf(" [%s%s]", item.keyEquivalentModifierMask & NSEventModifierFlagCommand ? "cmd-" : "",
                   str(item.keyEquivalent));
        if (item.action)
            printf(" -> %s on %s", sel_getName(item.action),
                   item.target ? object_getClassName(item.target) : "the first responder");
        printf("\n");
        if (item.submenu)
            show_menu(item.submenu, depth + 1);
    }
}

static NSEvent *key(NSString *chars)
{
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                           timestamp:0 windowNumber:0 context:nil characters:chars
         charactersIgnoringModifiers:chars isARepeat:NO keyCode:0];
}

- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    printf("launched; NSApp's delegate is this object: %s\n", yes(NSApp.delegate == self));

    printf("main menu \"%s\":\n", str(NSApp.mainMenu.title));
    show_menu(NSApp.mainMenu, 1);
    printf("windows menu: %s\n", str(NSApp.windowsMenu.title));

    NSWindow *w = self.window;
    printf("window: %s \"%s\", content %s, visible %s, style %lu, min size %s\n", object_getClassName(w),
           str(w.title), NSStringFromSize(w.contentView.frame.size).UTF8String, yes(w.isVisible),
           (unsigned long)w.styleMask, NSStringFromSize(w.minSize).UTF8String);
    for (NSView *v in w.contentView.subviews)
        printf("  %s %s mask %lu%s\n", object_getClassName(v), NSStringFromRect(v.frame).UTF8String,
               (unsigned long)v.autoresizingMask, v.superview == w.contentView ? "" : " (wrong superview)");

    NSTextField *f = self.nameField;
    printf("name field: \"%s\" placeholder \"%s\" editable %s bezeled %s draws background %s font %s %g\n",
           str(f.stringValue), str(f.placeholderString), yes(f.isEditable), yes(f.isBezeled), yes(f.drawsBackground),
           f.font ? "set" : "unset", f.font.pointSize);
    printf("secure field: %s, placeholder \"%s\"\n", object_getClassName(self.secureField),
           str(self.secureField.placeholderString));
    printf("label: \"%s\" editable %s draws background %s lines %ld\n", str(self.label.stringValue),
           yes(self.label.isEditable), yes(self.label.drawsBackground), (long)self.label.maximumNumberOfLines);
    NSButton *b = self.greetButton;
    printf("greet button: \"%s\" key equivalent is Return %s, bezel %lu, target is the delegate %s, action %s, "
           "cell %s\n",
           str(b.title), yes([b.keyEquivalent isEqualToString:@"\r"]), (unsigned long)b.bezelStyle,
           yes(b.target == self), sel_getName(b.action), object_getClassName(b.cell));
    printf("loud box: \"%s\" state %ld\n", str(self.loudBox.title), (long)self.loudBox.state);
    ColorSwatch *s = self.swatch;
    printf("swatch: %s, made with initWithFrame: %s, awoke %s, name %s, corner %ld\n", object_getClassName(s),
           yes(s.madeWithFrame), yes(s.awoke), str(s.swatchName), (long)s.corner);
    printf("swapped: %s \"%s\" enabled %s awoke %s\n", object_getClassName(self.swapped), str(self.swapped.title),
           yes(self.swapped.isEnabled), yes(self.swapped.awoke));
    printf("unknown view class falls back to %s\n", object_getClassName(self.unknownView));
    printf("key views: field -> %s -> %s\n", object_getClassName(f.nextKeyView),
           object_getClassName(f.nextKeyView.nextKeyView));

    /* It draws: the swatch's teal shows in the window's content. */
    NSView *content = w.contentView;
    NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
    [content cacheDisplayInRect:content.bounds toBitmapImageRep:rep];
    NSColor *c = [rep colorAtX:40 y:(NSInteger)(content.bounds.size.height - 110)];
    printf("swatch pixel: %.2f %.2f %.2f\n", c.redComponent, c.greenComponent, c.blueComponent);

    /* Actions and menu shortcuts. */
    [self.greetButton performClick:nil];
    [self.loudBox performClick:nil];
    [self.greetButton performClick:nil];
    printf("cmd-h handled: %s\n", yes([NSApp.mainMenu performKeyEquivalent:key(@"h")]));

    /* A second nib, loaded by the program, with its own owner. */
    PanelController *pc = [[PanelController alloc] init];
    NSArray *top = nil;
    BOOL ok = [[NSBundle mainBundle] loadNibNamed:@"Panel" owner:pc topLevelObjects:&top];
    printf("Panel loaded: %s, %lu top-level objects:", yes(ok), (unsigned long)top.count);
    for (id o in top)
        printf(" %s", object_getClassName(o));
    printf("\npanel: %s \"%s\" visible %s; note \"%s\"; helper %s\n", object_getClassName(pc.panel),
           str(pc.panel.title), yes(pc.panel.isVisible), str(pc.note.stringValue), yes(pc.helper != nil));
    printf("missing nib: %s\n", yes([[NSBundle mainBundle] loadNibNamed:@"Nothing" owner:pc topLevelObjects:NULL]));

    printf("cmd-q:\n");
    fflush(stdout);
    [NSApp.mainMenu performKeyEquivalent:key(@"q")];
    printf("still running (should have quit)\n");
}
- (void)applicationWillTerminate:(NSNotification *)n { printf("applicationWillTerminate\n"); }
@end

int main(int argc, const char *argv[])
{
    return NSApplicationMain(argc, argv);
}
