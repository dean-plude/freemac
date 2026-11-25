/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSAccessibility (freemac 1.222, Ferry 0.46.0), with no display: the
 * names and their values, the roles views and windows answer, values an app
 * sets and reads back through both APIs, ignored views standing aside for
 * their children, an element of the app's own, pressing a button by its
 * action, the descriptions of roles and actions, and the older API answered
 * by a cell that overrides it, as Sequel Pro's tab bar does; and the kAX
 * names ShiftIt reads windows with. */
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

@interface Target : NSObject
@property int clicks;
@end
@implementation Target
- (void)hit:(id)sender { self.clicks++; }
@end

/* the older API, overridden, as PSMTabBarCell does */
@interface TabCell : NSObject
@property BOOL hide;
@end
@implementation TabCell
- (BOOL)accessibilityIsIgnored { return self.hide; }
- (id)accessibilityAttributeValue:(NSString *)attribute
{
    if ([attribute isEqualToString:NSAccessibilityRoleAttribute])
        return NSAccessibilityButtonRole;
    return [super accessibilityAttributeValue:attribute];
}
@end

static const char *str(id o) { return o ? [[o description] UTF8String] : "nil"; }

static const char *roles(NSArray *a)
{
    NSMutableArray *r = [NSMutableArray array];
    for (id o in a)
        [r addObject:[o accessibilityAttributeValue:NSAccessibilityRoleAttribute] ?: @"?"];
    return [[r componentsJoinedByString:@" "] UTF8String];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        printf("names: %s %s %s %s %s\n", str(NSAccessibilityRoleAttribute), str(NSAccessibilityButtonRole),
               str(NSAccessibilityPressAction), str(NSAccessibilityCloseButtonSubrole),
               str(NSAccessibilityFocusedUIElementChangedNotification));
        printf("kAX: %s %s %s %s\n", str((__bridge NSString *)kAXPressAction),
               str((__bridge NSString *)kAXZoomButtonAttribute), str((__bridge NSString *)kAXSheetRole),
               str((__bridge NSString *)kAXChildrenAttribute));

        /* a few views */
        NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(10, 10, 200, 100)];
        [root addSubview:box];
        NSButton *button = [NSButton buttonWithTitle:@"Save" target:nil action:NULL];
        button.frame = NSMakeRect(5, 5, 80, 24);
        [box addSubview:button];
        NSButton *check = [NSButton checkboxWithTitle:@"Remember" target:nil action:NULL];
        [box addSubview:check];
        NSTextField *label = [NSTextField labelWithString:@"Name"];
        NSTextField *field = [NSTextField textFieldWithString:@"Ann"];
        [root addSubview:label];
        [root addSubview:field];
        NSImageView *image = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
        image.image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
        image.image.accessibilityDescription = @"a padlock";
        [root addSubview:image];

        printf("roles: view %s, button %s, checkbox %s, label %s, field %s, image %s\n", str(root.accessibilityRole),
               str(button.accessibilityRole), str(check.accessibilityRole), str(label.accessibilityRole),
               str(field.accessibilityRole), str(image.accessibilityRole));
        printf("follows the protocol: %d, ignored: view %d, button %d\n",
               (int)[NSView conformsToProtocol:@protocol(NSAccessibility)], (int)root.accessibilityIsIgnored,
               (int)button.accessibilityIsIgnored);
        printf("button title %s, image label %s\n", str(button.accessibilityTitle), str(image.accessibilityLabel));
        printf("children of the root, past the plain view: %s\n", roles(root.accessibilityChildren));
        /* the views above are all plain, so none is the button's parent yet */
        printf("the button's parent: %s\n", str(button.accessibilityParent));
        printf("unignored ancestor of the plain view: %s\n",
               NSAccessibilityUnignoredAncestor(box) == nil ? "none" : "found");
        NSRect f = button.accessibilityFrame;
        printf("button frame with no window: %.0f,%.0f %.0fx%.0f; AXPosition %s, AXSize %s\n", f.origin.x,
               f.origin.y, f.size.width, f.size.height,
               [NSStringFromPoint([[button accessibilityAttributeValue:NSAccessibilityPositionAttribute] pointValue])
                   UTF8String],
               [NSStringFromSize([[button accessibilityAttributeValue:NSAccessibilitySizeAttribute] sizeValue])
                   UTF8String]);

        /* values set through one API and read through the other */
        button.accessibilityLabel = @"Save the document";
        button.toolTip = @"Saves";
        [field accessibilitySetValue:@YES forAttribute:NSAccessibilityFocusedAttribute];
        printf("AXDescription %s, AXHelp %s, AXEnabled %s, AXFocused %s, settable %d %d\n",
               str([button accessibilityAttributeValue:NSAccessibilityDescriptionAttribute]),
               str([button accessibilityAttributeValue:NSAccessibilityHelpAttribute]),
               str([button accessibilityAttributeValue:NSAccessibilityEnabledAttribute]),
               str([field accessibilityAttributeValue:NSAccessibilityFocusedAttribute]),
               (int)[field accessibilityIsAttributeSettable:NSAccessibilityFocusedAttribute],
               (int)[field accessibilityIsAttributeSettable:NSAccessibilityRoleAttribute]);
        button.enabled = NO;
        printf("disabled: %d\n", (int)button.isAccessibilityEnabled);
        button.enabled = YES;
        [label accessibilitySetOverrideValue:@"heading" forAttribute:NSAccessibilityRoleDescriptionAttribute];
        printf("overridden: %s, listed %d\n",
               str([label accessibilityAttributeValue:NSAccessibilityRoleDescriptionAttribute]),
               (int)[[label accessibilityAttributeNames] containsObject:NSAccessibilityRoleDescriptionAttribute]);
        root.accessibilityElement = YES;
        root.accessibilityRole = NSAccessibilityGroupRole;
        printf("a view made an element: ignored %d, the button's parent now, past the plain view: %d\n",
               (int)root.accessibilityIsIgnored, (int)(button.accessibilityParent == root));
        printf("child count %lu, index of the field %lu\n",
               (unsigned long)[root accessibilityArrayAttributeCount:NSAccessibilityChildrenAttribute],
               (unsigned long)[root accessibilityIndexOfChild:field]);

        /* pressing a button by its action */
        Target *t = [Target new];
        button.target = t;
        button.action = @selector(hit:);
        printf("actions %s, ", [[[button accessibilityActionNames] componentsJoinedByString:@","] UTF8String]);
        [button accessibilityPerformAction:NSAccessibilityPressAction];
        BOOL pressed = [button accessibilityPerformPress];
        printf("clicks %d, pressed %d, described %s\n", t.clicks, (int)pressed,
               str([button accessibilityActionDescription:NSAccessibilityPressAction]));

        /* descriptions */
        printf("descriptions: %s; %s; %s; %s; %s; %s\n",
               str(NSAccessibilityRoleDescription(NSAccessibilityPopUpButtonRole, nil)),
               str(NSAccessibilityRoleDescription(NSAccessibilityWindowRole, NSAccessibilityStandardWindowSubrole)),
               str(NSAccessibilityRoleDescription(NSAccessibilityCheckBoxRole, nil)),
               str(NSAccessibilityRoleDescriptionForUIElement(button)),
               str(NSAccessibilityActionDescription(NSAccessibilityShowMenuAction)),
               str(NSAccessibilityActionDescription(NSAccessibilityShowAlternateUIAction)));

        /* a window and the application */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 320, 240)
                                                  styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                                      defer:NO];
        w.title = @"Inspector";
        NSButton *ok = [NSButton buttonWithTitle:@"OK" target:nil action:NULL];
        ok.frame = NSMakeRect(10, 20, 60, 24);
        [w.contentView addSubview:ok];
        printf("window: %s %s, children %s, parent is the app %d, app role %s, window listed %d\n",
               str(w.accessibilityRole), str(w.accessibilityTitle), roles(w.accessibilityChildren),
               (int)(w.accessibilityParent == NSApp), str(NSApp.accessibilityRole),
               (int)[NSApp.accessibilityWindows containsObject:w]);
        NSRect of = ok.accessibilityFrame;
        printf("button on the screen at %.0f,%.0f, its window %d, hit %s\n", of.origin.x, of.origin.y,
               (int)(ok.accessibilityWindow == w),
               [w accessibilityHitTest:NSMakePoint(of.origin.x + 5, of.origin.y + 5)] == ok ? "the button" : "?");

        /* an element of the app's own */
        NSAccessibilityElement *strip = [NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityGroupRole
                                                                                       frame:NSMakeRect(0, 0, 100, 20)
                                                                                       label:@"tabs" parent:nil];
        NSAccessibilityElement *tab = [NSAccessibilityElement new];
        tab.accessibilityRole = NSAccessibilityRadioButtonRole;
        tab.accessibilityFrameInParentSpace = NSMakeRect(30, 2, 20, 16);
        [strip accessibilityAddChildElement:tab];
        strip.accessibilityFrame = NSMakeRect(200, 300, 100, 20);
        NSRect tf = tab.accessibilityFrame;
        printf("element: %s, child %s at %.0f,%.0f, parent %d, ignored %d, hit %s\n", str(strip.accessibilityLabel),
               roles(strip.accessibilityChildren), tf.origin.x, tf.origin.y, (int)(tab.accessibilityParent == strip),
               (int)tab.accessibilityIsIgnored,
               [strip accessibilityHitTest:NSMakePoint(235, 305)] == tab ? "the tab" : "?");

        /* the older API, from an object that answers it itself */
        TabCell *a = [TabCell new], *b = [TabCell new];
        b.hide = YES;
        printf("unignored cells: %lu of 2, role %s, ancestor of the hidden one %s\n",
               (unsigned long)NSAccessibilityUnignoredChildren(@[ a, b ]).count,
               str([a accessibilityAttributeValue:NSAccessibilityRoleAttribute]),
               NSAccessibilityUnignoredAncestor(b) ? "found" : "none");

        NSAccessibilityPostNotification(button, NSAccessibilityValueChangedNotification);
        NSAccessibilityPostNotificationWithUserInfo(
            NSApp, NSAccessibilityAnnouncementRequestedNotification,
            @{NSAccessibilityAnnouncementKey : @"Saved", NSAccessibilityPriorityKey : @(NSAccessibilityPriorityHigh)});
        @try {
            NSAccessibilityRaiseBadArgumentException(button, NSAccessibilityValueAttribute, @3);
        } @catch (NSException *x) {
            printf("bad argument: %s\n", [x.name UTF8String]);
        }
    }
    return 0;
}
