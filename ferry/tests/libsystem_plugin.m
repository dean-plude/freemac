/* SPDX-License-Identifier: GPL-3.0-or-later
 * Plug-in bundles, as apps load them: NSBundle load, principalClass,
 * classNamed: and bundleForClass:, and the same bundles through
 * CFBundle's calls (CFBundleGetFunctionPointerForName...). The bundles
 * are built by run.sh into build/plugin_bundles, next to this program. */
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <objc/runtime.h>
#include <dlfcn.h>

/* Greeter's method, which this program only knows by name. */
@interface NSObject (Greeting)
- (NSString *)greeting;
@end

static const char *yes(BOOL ok) { return ok ? "yes" : "NO"; }

int main(void)
{
    @autoreleasepool {
        NSBundle *main = [NSBundle mainBundle];
        NSString *dir = [[[main executablePath] stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"plugin_bundles"];

        printf("Greeter.bundle\n");
        NSString *path = [dir stringByAppendingPathComponent:@"Greeter.bundle"];
        NSBundle *b = [NSBundle bundleWithPath:path];
        printf("  found: %s, identifier %s\n", yes(b != nil), [[b bundleIdentifier] UTF8String]);
        printf("  loaded before load: %s, description says so: %s\n", [b isLoaded] ? "yes" : "no",
               yes([[b description] hasSuffix:@"(not yet loaded)"]));
        printf("  program: %s, plug-ins folder: %s\n", [[[b executablePath] lastPathComponent] UTF8String],
               [[[b builtInPlugInsPath] substringFromIndex:[path length] + 1] UTF8String]);
        printf("  the same path gives the same bundle: %s\n", yes([NSBundle bundleWithPath:path] == b));
        printf("  Greeter before load: %s\n", NSClassFromString(@"Greeter") ? "found" : "nil");
        NSError *error = nil;
        printf("  preflight: %s\n", yes([b preflightAndReturnError:&error]));
        printf("  load: %s, loaded now: %s\n", yes([b loadAndReturnError:&error]), yes([b isLoaded]));
        printf("  load again: %s\n", yes([b load]));
        Class principal = [b principalClass];
        printf("  principal class: %s, is Greeter: %s\n", principal ? class_getName(principal) : "Nil",
               yes(principal == NSClassFromString(@"Greeter")));
        id greeter = [[principal alloc] init];
        printf("  its greeting: %s\n", [[greeter greeting] UTF8String]);
        [greeter release];
        printf("  bundleForClass: Greeter is the bundle: %s, NSString is the main bundle: %s, NSObject too: %s\n",
               yes([NSBundle bundleForClass:principal] == b), yes([NSBundle bundleForClass:[NSString class]] == main),
               yes([NSBundle bundleForClass:[NSObject class]] == main));
        printf("  classNamed: GreeterHelper %s, NSString %s\n",
               [b classNamed:@"GreeterHelper"] ? "found" : "nil", [b classNamed:@"NSString"] ? "found" : "nil");
        printf("  bundleWithIdentifier: finds it: %s\n",
               yes([NSBundle bundleWithIdentifier:@"org.freemac.ferry.greeter"] == b));
        printf("  unload: %s, still loaded: %s\n", [b unload] ? "yes" : "no", yes([b isLoaded]));

        printf("through CFBundle\n");
        CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:path];
        CFBundleRef cfb = CFBundleCreate(kCFAllocatorDefault, url);
        printf("  CFBundleCreate is the same bundle: %s\n", yes((id)cfb == b));
        printf("  CFBundleIsExecutableLoaded: %s\n", yes(CFBundleIsExecutableLoaded(cfb)));
        int (*answer)(void) = (int (*)(void))CFBundleGetFunctionPointerForName(cfb, CFSTR("greeter_answer"));
        printf("  CFBundleGetFunctionPointerForName greeter_answer(): %d\n", answer ? answer() : -1);
        const char *word = (const char *)CFBundleGetDataPointerForName(cfb, CFSTR("greeter_word"));
        printf("  CFBundleGetDataPointerForName greeter_word: %s\n", word ? word : "(null)");
        printf("  a name it lacks: %s\n", CFBundleGetFunctionPointerForName(cfb, CFSTR("no_such_function")) ? "found" : "NULL");
        CFURLRef exe = CFBundleCopyExecutableURL(cfb);
        printf("  CFBundleCopyExecutableURL: %s\n", [[(NSURL *)exe lastPathComponent] UTF8String]);
        CFRelease(exe);
        printf("  CFBundleGetBundleWithIdentifier: %s\n",
               yes((id)CFBundleGetBundleWithIdentifier(CFSTR("org.freemac.ferry.greeter")) == b));
        CFRelease(cfb);

        printf("Plain.bundle, with no NSPrincipalClass\n");
        cfb = CFBundleCreate(kCFAllocatorDefault, (CFURLRef)[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"Plain.bundle"]]);
        printf("  loaded before: %s\n", CFBundleIsExecutableLoaded(cfb) ? "yes" : "no");
        printf("  CFBundleLoadExecutable: %s\n", yes(CFBundleLoadExecutable(cfb)));
        principal = [(NSBundle *)cfb principalClass];
        printf("  principal class, the first it defines: %s\n", principal ? class_getName(principal) : "Nil");
        CFRelease(cfb);

        printf("Broken.bundle, whose program is missing\n");
        b = [NSBundle bundleWithPath:[dir stringByAppendingPathComponent:@"Broken.bundle"]];
        error = nil;
        BOOL ok = [b loadAndReturnError:&error];
        printf("  load: %s, error %s %ld\n", ok ? "yes" : "no", [[error domain] UTF8String], (long)[error code]);
        printf("  principal class: %s\n", [b principalClass] ? "found" : "Nil");
        printf("  a folder that isn't there: %s\n",
               [NSBundle bundleWithPath:[dir stringByAppendingPathComponent:@"Nothing.bundle"]] ? "found" : "nil");

        /* a bundle whose program was opened with dlopen, never through
         * NSBundle, is still known by its identifier, as a Mac knows a
         * loaded framework's (freemac 1.224) */
        printf("Quiet.bundle, opened with dlopen\n");
        NSString *quiet = [dir stringByAppendingPathComponent:@"Quiet.bundle"];
        printf("  by identifier before: %s\n",
               [NSBundle bundleWithIdentifier:@"org.freemac.ferry.quiet"] ? "found" : "nil");
        void *h = dlopen([[quiet stringByAppendingPathComponent:@"Contents/MacOS/Quiet"] fileSystemRepresentation],
                         RTLD_NOW);
        printf("  dlopen: %s\n", yes(h != NULL));
        b = [NSBundle bundleWithIdentifier:@"org.freemac.ferry.quiet"];
        printf("  by identifier after: %s, its folder %s\n", b ? "found" : "nil", [[[b bundlePath] lastPathComponent] UTF8String]);
        printf("  in allBundles: %s, in allFrameworks: %s\n", yes([[NSBundle allBundles] containsObject:b]),
               [[NSBundle allFrameworks] containsObject:b] ? "yes" : "no");
        printf("main bundle loaded: %s\n", yes([main isLoaded]));
    }
    return 0;
}
