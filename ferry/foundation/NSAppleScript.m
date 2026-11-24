/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSAppleScript. There is no AppleScript here, and no
 * Mac applications to send its Apple events to, so a script keeps its
 * source and is never compiled or run: compiling answers NO and running
 * answers nil, each with the error dictionary Apple documents, and the
 * first time a program tries, Ferry says so once on standard error. A
 * program that checks for the error carries on without the script's
 * result.
 *
 * Written from Apple's public documentation of NSAppleScript; no Apple code
 * was used. */
#import "FInternal.h"
#import <Foundation/NSAppleScript.h>

NSString *const NSAppleScriptErrorMessage = @"NSAppleScriptErrorMessage";
NSString *const NSAppleScriptErrorNumber = @"NSAppleScriptErrorNumber";
NSString *const NSAppleScriptErrorAppName = @"NSAppleScriptErrorAppName";
NSString *const NSAppleScriptErrorBriefMessage = @"NSAppleScriptErrorBriefMessage";
NSString *const NSAppleScriptErrorRange = @"NSAppleScriptErrorRange";

/* errOSASystemError, the Open Scripting Architecture's general failure */
enum { F_OSA_SYSTEM_ERROR = -1750 };

static void say_once(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fprintf(stderr, "ferry: AppleScript isn't supported; NSAppleScript runs no scripts and answers an error\n");
    });
}

@implementation NSAppleScript {
    NSString *_source;
}

- (instancetype)initWithSource:(NSString *)source
{
    if ((self = [super init]))
        _source = [source copy];
    return self;
}
- (instancetype)init { return [self initWithSource:nil]; }
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSDictionary<NSString *, id> **)errorInfo
{
    NSString *s = [url isFileURL] ? [NSString stringWithContentsOfFile:[url path] encoding:NSUTF8StringEncoding
                                                                  error:NULL]
                                  : nil;
    if (!s) {
        /* a compiled script (.scpt) or a file that can't be read */
        if (errorInfo)
            *errorInfo = @{
                NSAppleScriptErrorMessage : @"The script couldn't be read.",
                NSAppleScriptErrorBriefMessage : @"The script couldn't be read.",
                NSAppleScriptErrorNumber : @(-43), /* fnfErr */
                NSAppleScriptErrorAppName : [[NSProcessInfo processInfo] processName] ?: @"",
            };
        [self release];
        return nil;
    }
    return [self initWithSource:s];
}
- (void)dealloc
{
    [_source release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [[NSAppleScript allocWithZone:zone] initWithSource:_source]; }

- (NSString *)source { return _source; }
- (BOOL)isCompiled { return NO; }

- (NSDictionary *)_ferryError
{
    say_once();
    NSString *message = @"AppleScript isn't available in Ferry, so the script can't be compiled or run.";
    return @{
        NSAppleScriptErrorMessage : message,
        NSAppleScriptErrorBriefMessage : @"AppleScript isn't available.",
        NSAppleScriptErrorNumber : @(F_OSA_SYSTEM_ERROR),
        NSAppleScriptErrorAppName : [[NSProcessInfo processInfo] processName] ?: @"",
        NSAppleScriptErrorRange : [NSValue valueWithRange:NSMakeRange(0, [_source length])],
    };
}
- (BOOL)compileAndReturnError:(NSDictionary<NSString *, id> **)errorInfo
{
    NSDictionary *e = [self _ferryError];
    if (errorInfo)
        *errorInfo = e;
    return NO;
}
- (NSAppleEventDescriptor *)executeAndReturnError:(NSDictionary<NSString *, id> **)errorInfo
{
    NSDictionary *e = [self _ferryError];
    if (errorInfo)
        *errorInfo = e;
    return nil;
}
- (NSAppleEventDescriptor *)executeAppleEvent:(NSAppleEventDescriptor *)event error:(NSDictionary<NSString *, id> **)errorInfo
{
    return [self executeAndReturnError:errorInfo];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSAppleScript %p, %lu characters of source, not compiled>", self,
                                      (unsigned long)[_source length]];
}
@end
