/* SPDX-License-Identifier: GPL-3.0-or-later
 * The font manager and the font panel (freemac 1.NEXT, Ferry 0.NEXT): one
 * shared manager (a nib's or a program's own alloc gives it too); the
 * installed families and their members, from fontconfig; fonts made by
 * family, traits and weight; conversions to and from bold and italic, to
 * another size, family and face, and heavier; Bold and Italic menu items
 * (addFontTrait:) turning the trait on and off in a text view's selection
 * through changeFont:, and the menu items' checks following the selected
 * font; Bigger (modifyFont:); typing after Bold; and the font panel,
 * answered from the environment with no display, changing only what was
 * chosen. The test uses DejaVu Serif, which fontconfig on the test system
 * has. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

static void show(const char *what, NSFont *f)
{
    NSFontManager *fm = [NSFontManager sharedFontManager];
    NSFontTraitMask t = [fm traitsOfFont:f];
    printf("%s: %s %g, %s%s%s weight %ld\n", what, [[f familyName] UTF8String], [f pointSize],
           t & NSBoldFontMask ? "bold " : "", t & NSItalicFontMask ? "italic " : "",
           t & NSFixedPitchFontMask ? "fixed " : "", (long)[fm weightOfFont:f]);
}

static void runs(const char *what, NSTextView *tv)
{
    NSTextStorage *s = [tv textStorage];
    printf("%s:", what);
    for (NSUInteger i = 0; i < [s length];) {
        NSRange r;
        NSFont *f = [s attribute:NSFontAttributeName atIndex:i longestEffectiveRange:&r
                         inRange:NSMakeRange(0, [s length])];
        NSFontTraitMask t = [[NSFontManager sharedFontManager] traitsOfFont:f];
        printf(" [%s|%s%s%g]", [[[s string] substringWithRange:r] UTF8String], t & NSBoldFontMask ? "B" : "",
               t & NSItalicFontMask ? "I" : "", [f pointSize]);
        i = NSMaxRange(r);
    }
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        unsetenv("FERRY_FONT_ANSWER");
        [NSApplication sharedApplication];
        NSFontManager *fm = [NSFontManager sharedFontManager];
        printf("one manager: %d %d, action %s\n", fm == [NSFontManager sharedFontManager],
               fm == [[NSFontManager alloc] init], sel_getName([fm action]));

        NSArray *families = [fm availableFontFamilies];
        printf("families: DejaVu Serif %d, DejaVu Sans Mono %d, sorted %d, no generic Sans %d\n",
               [families containsObject:@"DejaVu Serif"], [families containsObject:@"DejaVu Sans Mono"],
               [families isEqual:[families sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]],
               ![families containsObject:@"Sans"] && ![families containsObject:@"Monospace"]);
        NSArray *members = [fm availableMembersOfFontFamily:@"DejaVu Serif"];
        BOOL regular = NO, bold = NO, italic = NO;
        for (NSArray *m in members) {
            NSFontTraitMask t = [m[3] unsignedIntegerValue];
            if ([m[0] isEqual:@"DejaVuSerif-Regular"] && [m[2] integerValue] == 5 && !(t & NSBoldFontMask))
                regular = YES;
            if ([m[0] isEqual:@"DejaVuSerif-Bold"] && [m[2] integerValue] == 9 && (t & NSBoldFontMask))
                bold = YES;
            if ((t & NSItalicFontMask) && !(t & NSBoldFontMask))
                italic = YES;
        }
        printf("DejaVu Serif members: regular %d, bold %d, italic %d, four fields %d\n", regular, bold, italic,
               [members count] && [members[0] count] == 4);
        printf("unknown family: %d members\n", (int)[[fm availableMembersOfFontFamily:@"No Such Family"] count]);
        NSArray *fonts = [fm availableFonts];
        printf("fonts: DejaVuSerif-Bold %d; bold fonts include it %d, unbold fonts don't %d\n",
               [fonts containsObject:@"DejaVuSerif-Bold"],
               [[fm availableFontNamesWithTraits:NSBoldFontMask] containsObject:@"DejaVuSerif-Bold"],
               ![[fm availableFontNamesWithTraits:NSUnboldFontMask] containsObject:@"DejaVuSerif-Bold"]);
        printf("fixed pitch: mono %d, serif %d\n", [fm fontNamed:@"DejaVuSansMono" hasTraits:NSFixedPitchFontMask],
               [fm fontNamed:@"DejaVuSerif" hasTraits:NSFixedPitchFontMask]);

        /* making fonts */
        NSFont *serif = [fm fontWithFamily:@"DejaVu Serif" traits:0 weight:5 size:12];
        show("DejaVu Serif, weight 5", serif);
        show("bold italic", [fm fontWithFamily:@"dejavu serif" traits:NSBoldFontMask | NSItalicFontMask weight:5
                                          size:14]);
        show("weight 9", [fm fontWithFamily:@"DejaVu Serif" traits:0 weight:9 size:12]);
        printf("no such family: %d; a Mac family (Menlo) %d\n",
               [fm fontWithFamily:@"No Such Family" traits:0 weight:5 size:12] != nil,
               [fm fontWithFamily:@"Menlo" traits:0 weight:5 size:12] != nil);

        /* converting */
        NSFont *b = [fm convertFont:serif toHaveTrait:NSBoldFontMask];
        show("to bold", b);
        show("to italic", [fm convertFont:b toHaveTrait:NSItalicFontMask]);
        show("bold taken off", [fm convertFont:b toNotHaveTrait:NSBoldFontMask]);
        show("unbold", [fm convertFont:b toHaveTrait:NSUnboldFontMask]);
        show("to 20 points", [fm convertFont:serif toSize:20]);
        show("to DejaVu Sans Mono", [fm convertFont:b toFamily:@"DejaVu Sans Mono"]);
        show("to the Bold face", [fm convertFont:serif toFace:@"DejaVuSerif-Bold"]);
        show("heavier", [fm convertWeight:YES ofFont:serif]);
        show("lighter than bold", [fm convertWeight:NO ofFont:b]);
        printf("with no action, convertFont: gives the same font %d\n", [fm convertFont:serif] == serif);
        printf("localized name: %s\n", [[fm localizedNameForFamily:@"DejaVu Serif" face:@"Bold"] UTF8String]);

        /* Bold and Italic in a text view */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 100)
                                                  styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                                      defer:YES];
        [w setReleasedWhenClosed:NO];
        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
        [w setContentView:tv];
        [w makeKeyAndOrderFront:nil];
        [w makeFirstResponder:tv];
        [tv setString:@"one two three"];
        [tv setFont:serif];
        printf("text view uses the font panel %d\n", [tv usesFontPanel]);
        NSMenu *menu = [fm fontMenu:YES];
        NSMenuItem *boldItem = [menu itemWithTitle:@"Bold"], *italicItem = [menu itemWithTitle:@"Italic"];
        printf("font menu: %ld items, Bold tag %ld, Italic tag %ld\n", (long)[menu numberOfItems],
               (long)[boldItem tag], (long)[italicItem tag]);
        [tv setSelectedRange:NSMakeRange(4, 3)];
        show("selected font", [fm selectedFont]);
        [fm validateMenuItem:boldItem];
        printf("Bold checked %d\n", [boldItem state] == NSControlStateValueOn);
        [NSApp sendAction:[boldItem action] to:[boldItem target] from:boldItem];
        runs("Bold", tv);
        [fm validateMenuItem:boldItem];
        printf("Bold checked %d, action now %ld\n", [boldItem state] == NSControlStateValueOn,
               (long)[fm currentFontAction]);
        [tv setSelectedRange:NSMakeRange(0, 7)];
        [NSApp sendAction:[italicItem action] to:[italicItem target] from:italicItem];
        runs("Italic over two runs", tv);
        [tv setSelectedRange:NSMakeRange(4, 3)];
        [NSApp sendAction:[boldItem action] to:[boldItem target] from:boldItem];
        runs("Bold again: off", tv);
        [tv setSelectedRange:NSMakeRange(8, 5)];
        [NSApp sendAction:@selector(modifyFont:) to:fm from:[menu itemWithTitle:@"Bigger"]];
        runs("Bigger", tv);
        [tv setSelectedRange:NSMakeRange(13, 0)];
        [NSApp sendAction:[boldItem action] to:[boldItem target] from:boldItem];
        [tv insertText:@" four"];
        runs("typed after Bold", tv);

        /* the font panel, answered with no display */
        setenv("FERRY_FONT_ANSWER", "DejaVu Sans Mono 18", 1);
        [tv setSelectedRange:NSMakeRange(0, 7)];
        [fm orderFrontFontPanel:nil];
        NSFontPanel *panel = [NSFontPanel sharedFontPanel];
        printf("panel shared %d, exists %d, visible %d\n", panel == [fm fontPanel:NO],
               [NSFontPanel sharedFontPanelExists], [panel isVisible]);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        runs("chosen in the panel", tv);
        printf("visible after %d\n", [panel isVisible]);
        /* only the size, this time: each run keeps its family */
        NSFont *shownFont = [fm selectedFont];
        setenv("FERRY_FONT_ANSWER", [[NSString stringWithFormat:@"%@ 9", [shownFont familyName]] UTF8String], 1);
        [tv setSelectedRange:NSMakeRange(0, [[tv string] length])];
        [panel setPanelFont:shownFont isMultiple:YES];
        [panel orderFront:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        runs("only the size chosen", tv);
        NSMutableSet *names = [NSMutableSet set];
        NSTextStorage *s = [tv textStorage];
        for (NSUInteger i = 0; i < [s length]; i++)
            [names addObject:[[s attribute:NSFontAttributeName atIndex:i effectiveRange:NULL] familyName]];
        printf("families kept: %s\n",
               [[[[names allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]
                   UTF8String]);
    }
    return 0;
}
