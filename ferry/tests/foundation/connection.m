/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSConnection between two programs (Distributed Objects), as MacVim's
 * window app and its Vim processes use it: the program registers a name
 * with a protocol checker as its root object and starts itself again
 * (through NSTask); the other program finds the name, sends messages to
 * the root proxy (results, out arguments, structs, exceptions, oneway
 * messages, a collection by copy) and hands over an object of its own by
 * reference, which the first program calls back while the call is under
 * way. Built without ARC, as MacVim is. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

#define NAME @"org.freemac.test.connection"

@protocol ClientProtocol
- (int)ping:(int)n;
- (oneway void)note:(in bycopy NSString *)s;
@end

@protocol ServerProtocol
- (NSString *)greet:(NSString *)who;
- (unsigned long)connectClient:(byref in id<ClientProtocol>)client pid:(int)pid;
- (oneway void)post:(in bycopy NSArray *)queue;
- (BOOL)divide:(int)a by:(int)b result:(out int *)result error:(out bycopy NSString **)error;
- (NSRange)rangeFor:(int)n;
- (void)fail;
- (NSArray *)list;
- (id)echo:(id)o;
@end

static NSMutableArray *said; /* what the first program saw, printed at the end */

@interface Server : NSObject <ServerProtocol> {
  @public
    id client;
    BOOL done;
}
- (void)secret;
@end
@implementation Server
- (NSString *)greet:(NSString *)who { return [@"hello " stringByAppendingString:who]; }
- (unsigned long)connectClient:(byref in id<ClientProtocol>)c pid:(int)pid
{
    client = [(id)c retain];
    [(NSDistantObject *)c setProtocolForProxy:@protocol(ClientProtocol)];
    [said addObject:[NSString stringWithFormat:@"the client is a proxy: %d", [(id)c isProxy]]];
    [said addObject:[NSString stringWithFormat:@"its pid came: %d", pid > 0]];
    int back = [c ping:7];
    [said addObject:[NSString stringWithFormat:@"pinged it back while connecting: %d", back]];
    [c note:@"welcome"];
    return 42;
}
- (oneway void)post:(in bycopy NSArray *)queue
{
    [said addObject:[NSString stringWithFormat:@"posted: %@", [queue componentsJoinedByString:@","]]];
    if ([[queue lastObject] isEqual:@"done"])
        done = YES;
}
- (BOOL)divide:(int)a by:(int)b result:(out int *)result error:(out bycopy NSString **)error
{
    if (!b) {
        *error = @"division by zero";
        return NO;
    }
    *result = a / b;
    return YES;
}
- (NSRange)rangeFor:(int)n { return NSMakeRange(n, n * 10); }
- (void)fail { [NSException raise:@"TestException" format:@"failed on purpose"]; }
- (NSArray *)list { return @[ @"a", @"b", @3 ]; }
- (id)echo:(id)o { return o; }
- (void)secret {}
@end

@interface Client : NSObject <ClientProtocol>
@end
@implementation Client
- (int)ping:(int)n { return n * 6; }
- (oneway void)note:(in bycopy NSString *)s { printf("child: the server noted: %s\n", [s UTF8String]); }
@end

static int child(void)
{
    NSConnection *conn = [NSConnection connectionWithRegisteredName:NAME host:nil];
    printf("child: found the name: %d\n", conn != nil);
    id root = [conn rootProxy];
    [root setProtocolForProxy:@protocol(ServerProtocol)];
    printf("child: root is a proxy: %d, its connection: %d\n", [root isProxy], [root connectionForProxy] == conn);
    printf("child: %s\n", [[root greet:@"there"] UTF8String]);
    Client *me = [[Client alloc] init];
    printf("child: connected, answer %lu\n", [root connectClient:me pid:getpid()]);
    int r = 0;
    NSString *err = nil;
    BOOL ok = [root divide:7 by:2 result:&r error:&err];
    printf("child: 7/2: %d %d %s\n", ok, r, err ? [err UTF8String] : "(no error)");
    ok = [root divide:1 by:0 result:&r error:&err];
    printf("child: 1/0: %d %s\n", ok, [err UTF8String]);
    NSRange g = [root rangeFor:4];
    printf("child: range %lu %lu\n", (unsigned long)g.location, (unsigned long)g.length);
    @try {
        [root fail];
        printf("child: no exception\n");
    } @catch (NSException *e) {
        printf("child: caught %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
    }
    @try {
        [root secret];
        printf("child: secret went through\n");
    } @catch (NSException *e) {
        printf("child: secret refused\n");
    }
    printf("child: list %s\n", [[[root list] componentsJoinedByString:@" "] UTF8String]);
    printf("child: my object came back as itself: %d\n", [root echo:me] == me);
    printf("child: a string came back equal: %d\n", [[root echo:@"same"] isEqual:@"same"]);
    printf("child: unknown name: %s\n",
           [NSConnection connectionWithRegisteredName:@"org.freemac.test.none" host:nil] ? "found" : "nil");
    [root post:@[ [NSData dataWithBytes:"xy" length:2], @5, @"done" ]];
    /* the oneway post is in the socket before the program goes */
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    fflush(stdout);
    return 0;
}

static NSConnection *client_conn;
static BOOL died;

@interface Watcher : NSObject
@end
@implementation Watcher
- (void)died:(NSNotification *)n
{
    if ([n object] == client_conn)
        died = YES;
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "child"))
            return child();
        said = [[NSMutableArray alloc] init];
        Server *server = [[Server alloc] init];
        NSConnection *conn = [[NSConnection alloc] initWithReceivePort:[NSPort port] sendPort:nil];
        [conn setRootObject:[NSProtocolChecker protocolCheckerWithTarget:server protocol:@protocol(ServerProtocol)]];
        [conn setRequestTimeout:10];
        [conn setReplyTimeout:10];
        printf("registered: %d\n", [conn registerName:NAME]);
        NSConnection *other = [[[NSConnection alloc] init] autorelease];
        printf("same name again: %d\n", [other registerName:NAME]);
        fflush(stdout);
        Watcher *w = [[Watcher alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:w selector:@selector(died:)
                                                     name:NSConnectionDidDieNotification object:nil];
        NSTask *t = [[NSTask alloc] init];
        [t setLaunchPath:[[[NSProcessInfo processInfo] arguments] objectAtIndex:0]];
        [t setArguments:@[ @"child" ]];
        [t launch];
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
        while (!server->done && [limit timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        client_conn = [server->client connectionForProxy];
        [t waitUntilExit];
        while (!died && [limit timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        for (NSString *s in said)
            printf("%s\n", [s UTF8String]);
        printf("the other program exited %d\n", [t terminationStatus]);
        printf("its connection died: %d, valid %d\n", died, [client_conn isValid]);
        @try {
            [server->client ping:1];
            printf("a call after it went: no exception\n");
        } @catch (NSException *e) {
            printf("a call after it went: %s\n", [[e name] UTF8String]);
        }
        [conn invalidate];
        printf("after invalidate: found %d\n", [NSConnection connectionWithRegisteredName:NAME host:nil] != nil);
    }
    return 0;
}
