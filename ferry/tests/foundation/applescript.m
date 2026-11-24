/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.213, Ferry 0.39.0): NSAppleScript, which keeps its
 * source but compiles and runs nothing. Compiling answers NO and running
 * answers nil, each with Apple's error dictionary; a script read from a
 * file keeps the file's text, and a file that isn't there gives no script.
 * run.sh checks that Ferry says so on stderr once, however many scripts are
 * tried. KeyCastr and Spectacle run scripts this way. */
#import <Foundation/Foundation.h>
#include <unistd.h>

static void show(const char *what, NSDictionary *e)
{
    NSRange r = [e[NSAppleScriptErrorRange] rangeValue];
    printf("%s: number %ld, a message %s, a brief message %s, app name ours %s, range %lu,%lu\n", what,
           (long)[e[NSAppleScriptErrorNumber] integerValue], [e[NSAppleScriptErrorMessage] length] ? "yes" : "no",
           [e[NSAppleScriptErrorBriefMessage] length] ? "yes" : "no",
           [e[NSAppleScriptErrorAppName] isEqual:[[NSProcessInfo processInfo] processName]] ? "yes" : "no",
           (unsigned long)r.location, (unsigned long)r.length);
}

int main(void)
{
    @autoreleasepool {
        NSString *source = @"tell application \"Finder\" to get name of front window";
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
        printf("made: %s, source kept %s, compiled %s\n", script ? "yes" : "no",
               [[script source] isEqual:source] ? "yes" : "no", [script isCompiled] ? "yes" : "no");
        NSDictionary *error = nil;
        BOOL compiled = [script compileAndReturnError:&error];
        printf("compile: %s\n", compiled ? "yes" : "no");
        show("  its error", error);
        error = nil;
        id result = [script executeAndReturnError:&error];
        printf("execute: %s\n", result ? "a result" : "nil");
        show("  its error", error);
        printf("execute with no place for the error: %s\n", [script executeAndReturnError:NULL] ? "a result" : "nil");
        NSAppleScript *copy = [script copy];
        printf("a copy keeps the source: %s\n", [[copy source] isEqual:source] ? "yes" : "no");

        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                     [NSString stringWithFormat:@"ferry-script-%d.applescript", getpid()]];
        [@"beep" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *readError = nil;
        NSAppleScript *fromFile = [[NSAppleScript alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                                         error:&readError];
        printf("from a file: source %s, error %s\n", [[fromFile source] UTF8String], readError ? "yes" : "none");
        error = nil;
        printf("run from a file: %s\n", [fromFile executeAndReturnError:&error] ? "a result" : "nil");
        show("  its error", error);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        readError = nil;
        NSAppleScript *missing = [[NSAppleScript alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@"/nonexistent/x.scpt"]
                                                                        error:&readError];
        printf("from a missing file: %s, error number %ld\n", missing ? "a script" : "nil",
               (long)[readError[NSAppleScriptErrorNumber] integerValue]);
    }
    return 0;
}
