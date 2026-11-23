/* Key paths, value transformers and Cocoa bindings (M6), as the apps tried
 * in docs/ferry-compat.md use them. Bindings are recorded and set their
 * value once; they don't follow later changes yet. Runs with no display. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>

@interface Settings : NSObject
@property (copy) NSString *name;
@property (strong) Settings *inner;
@property BOOL enabled;
@end
@implementation Settings
@end

@interface Upper : NSValueTransformer
@end
@implementation Upper
+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value { return [value uppercaseString]; }
@end

@interface Swatch : NSView
@end
@implementation Swatch
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Settings *s = [Settings new], *inner = [Settings new];
        s.inner = inner;
        inner.name = @"deep";
        printf("valueForKeyPath: %s\n", [[s valueForKeyPath:@"inner.name"] UTF8String]);
        [s setValue:@"changed" forKeyPath:@"inner.name"];
        printf("setValue:forKeyPath: %s\n", inner.name.UTF8String);

        NSValueTransformer *neg = [NSValueTransformer valueTransformerForName:NSNegateBooleanTransformerName];
        printf("negate YES: %d, is nil(nil): %d, is not nil(@1): %d\n", [[neg transformedValue:@YES] boolValue],
               [[[NSValueTransformer valueTransformerForName:NSIsNilTransformerName] transformedValue:nil] boolValue],
               [[[NSValueTransformer valueTransformerForName:NSIsNotNilTransformerName] transformedValue:@1] boolValue]);
        printf("by class name: %s\n", [[[NSValueTransformer valueTransformerForName:@"Upper"] transformedValue:@"loud"] UTF8String]);
        NSData *archived = [[NSValueTransformer valueTransformerForName:NSSecureUnarchiveFromDataTransformerName]
            reverseTransformedValue:@[ @"a", @2 ]];
        NSArray *back = [[NSValueTransformer valueTransformerForName:NSSecureUnarchiveFromDataTransformerName]
            transformedValue:archived];
        printf("through archived data: %s\n", [[back componentsJoinedByString:@" "] UTF8String]);

        NSValue *weak = [NSValue valueWithNonretainedObject:s];
        printf("nonretained object: %s, objCType %s\n", weak.nonretainedObjectValue == s ? "same" : "different",
               weak.objCType);

        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-bindings.plist"];
        [@{ @"k" : @"v" } writeToFile:path atomically:YES];
        NSDictionary *d = [[NSDictionary alloc] initWithContentsOfFile:path];
        NSMutableDictionary *m = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
        [m setObject:@"w" forKey:@"k2"];
        printf("initWithContentsOfFile: %s, mutable %lu keys\n", [d[@"k"] UTF8String], (unsigned long)m.count);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        s.name = @"bound";
        s.enabled = NO;
        [Swatch exposeBinding:@"color"];
        [field bind:NSValueBinding toObject:s withKeyPath:@"name" options:nil];
        [box bind:NSEnabledBinding toObject:s withKeyPath:@"enabled" options:nil];
        [box bind:NSTitleBinding toObject:s withKeyPath:@"noSuchKey" options:nil];
        printf("bound field: %s, box enabled %s, title kept \"%s\"\n", field.stringValue.UTF8String,
               box.isEnabled ? "yes" : "no", box.title.UTF8String);
        NSDictionary *info = [field infoForBinding:NSValueBinding];
        printf("info: observed is the settings %s, key path %s\n",
               info[NSObservedObjectKey] == s ? "yes" : "no", [info[NSObservedKeyPathKey] UTF8String]);
        printf("exposed: %s\n", [[[[Swatch new] exposedBindings] componentsJoinedByString:@","] UTF8String]);
        /* a change made through key-value coding reaches the bound views */
        [s setValue:@"changed" forKey:@"name"];
        [s setValue:@YES forKey:@"enabled"];
        printf("after a change: field %s, box enabled %s\n", field.stringValue.UTF8String, box.isEnabled ? "yes" : "no");
        [field unbind:NSValueBinding];
        printf("after unbind: %s\n", [field infoForBinding:NSValueBinding] ? "still bound" : "unbound");
        [s setValue:@"not followed" forKey:@"name"];
        printf("unbound field kept: %s\n", field.stringValue.UTF8String);

        /* the user's defaults through their controller */
        NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];
        [udc.values setValue:@"first" forKey:@"FerryControllerTest"];
        NSTextField *pref = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        [pref bind:NSValueBinding toObject:udc withKeyPath:@"values.FerryControllerTest" options:nil];
        printf("defaults controller: field %s, defaults %s\n", pref.stringValue.UTF8String,
               [[[NSUserDefaults standardUserDefaults] stringForKey:@"FerryControllerTest"] UTF8String]);
        [udc.values setValue:@"second" forKey:@"FerryControllerTest"];
        printf("after a change: field %s\n", pref.stringValue.UTF8String);
        udc.appliesImmediately = NO;
        [udc.values setValue:@"third" forKey:@"FerryControllerTest"];
        printf("held: field %s, defaults %s, unapplied %d\n", pref.stringValue.UTF8String,
               [[[NSUserDefaults standardUserDefaults] stringForKey:@"FerryControllerTest"] UTF8String],
               udc.hasUnappliedChanges);
        [udc revert:nil];
        printf("reverted: field %s\n", pref.stringValue.UTF8String);
        [pref unbind:NSValueBinding];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"FerryControllerTest"];

        [[NSUserDefaults standardUserDefaults] setValue:@"kv" forKey:@"FerryBindingsTest"];
        printf("defaults by key-value coding: %s\n",
               [[[NSUserDefaults standardUserDefaults] valueForKey:@"FerryBindingsTest"] UTF8String]);
        [[NSUserDefaults standardUserDefaults] setValue:nil forKey:@"FerryBindingsTest"];
    }
    return 0;
}
