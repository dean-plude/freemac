/* JavaScriptCore: the C API as MacDown uses it (a script's global read back
 * as JSON) and the Objective-C API as Spectacle uses it (blocks taking
 * rectangles, an object whose JSExport protocol keeps a JavaScript function
 * that Objective-C calls later, and an exception handler), with the values
 * crossing both ways. Run by run.sh both with this system's JavaScriptCore
 * and with none, where the program must stop at its first call. */
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@protocol RegistryExports <JSExport>
- (void)registerCalculation:(JSValue *)calculation withAction:(NSString *)action;
- (NSString *)describe:(NSString *)what times:(int)n;
JSExportAs(add, -(double)addNumber:(double)a to:(double)b);
@property (copy) NSString *title;
@property (readonly) NSInteger count;
@end

@interface Registry : NSObject <RegistryExports>
@property (strong) NSMutableDictionary<NSString *, JSValue *> *calculations;
@end

@implementation Registry
@synthesize title = _title;
- (instancetype)init
{
    if ((self = [super init]))
        _calculations = [NSMutableDictionary dictionary];
    return self;
}
- (void)registerCalculation:(JSValue *)calculation withAction:(NSString *)action
{
    self.calculations[action] = calculation;
}
- (NSString *)describe:(NSString *)what times:(int)n
{
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < n; i++)
        [s appendString:what];
    return s;
}
- (double)addNumber:(double)a to:(double)b { return a + b; }
- (NSInteger)count { return (NSInteger)self.calculations.count; }
@end

static NSString *RectString(CGRect r)
{
    return [NSString stringWithFormat:@"{%g, %g, %g, %g}", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static void c_api(void)
{
    JSGlobalContextRef ctx = JSGlobalContextCreate(NULL);
    JSStringRef script = JSStringCreateWithCFString(CFSTR("var settings = {theme: 'dark', sizes: [1, 2, 3], on: true};"));
    JSValueRef exc = NULL;
    JSEvaluateScript(ctx, script, NULL, NULL, 0, &exc);
    JSStringRelease(script);
    JSStringRef name = JSStringCreateWithUTF8CString("settings");
    JSValueRef val = JSObjectGetProperty(ctx, JSContextGetGlobalObject(ctx), name, &exc);
    JSStringRelease(name);
    JSStringRef json = JSValueCreateJSONString(ctx, val, 0, &exc);
    NSString *s = (NSString *)CFBridgingRelease(JSStringCopyCFString(kCFAllocatorDefault, json));
    JSStringRelease(json);
    printf("C: %s, exception %s\n", s.UTF8String, exc ? "yes" : "no");

    JSStringRef bad = JSStringCreateWithUTF8CString("nosuch.thing");
    JSValueRef r = JSEvaluateScript(ctx, bad, NULL, NULL, 0, &exc);
    JSStringRelease(bad);
    JSStringRef msg = JSValueToStringCopy(ctx, exc, NULL);
    char buf[128];
    JSStringGetUTF8CString(msg, buf, sizeof buf);
    JSStringRelease(msg);
    printf("C: result %s, %s\n", r ? "a value" : "none", buf);
    printf("C: type of 2+2 is number %d, empty class version %d\n",
           JSValueGetType(ctx, JSValueMakeNumber(ctx, 4)) == kJSTypeNumber, kJSClassDefinitionEmpty.version);
    JSGlobalContextRelease(ctx);
}

int main(void)
{
    @autoreleasepool {
        c_api();

        JSContext *context = [JSContext new];
        __block NSString *lastError = nil;
        context.exceptionHandler = ^(JSContext *c, JSValue *exception) {
            lastError = [NSString stringWithFormat:@"%@: %@", [exception[@"name"] toString],
                                                   [exception[@"message"] toString]];
        };

        /* values both ways */
        JSValue *v = [context evaluateScript:@"[1, 'two', {three: 3}, null, true, 2.5]"];
        printf("array: %s\n", [[[v toArray] description] stringByReplacingOccurrencesOfString:@"\n" withString:@""]
                                  .UTF8String);
        printf("types: array %d, string %d, number %d, sum %d\n", v.isArray, v[1].isString, v[5].isNumber,
               [[context evaluateScript:@"40 + 2"] toInt32]);
        context[@"fromObjC"] = @{@"name" : @"Ferry", @"list" : @[ @1, @2 ], @"flag" : @YES};
        printf("dict: %s\n", [[context evaluateScript:@"JSON.stringify(fromObjC, Object.keys(fromObjC).sort())"]
                                  toString].UTF8String);
        printf("typeof flag: %s, list length %d\n",
               [[context evaluateScript:@"typeof fromObjC.flag"] toString].UTF8String,
               [[context evaluateScript:@"fromObjC.list.length"] toInt32]);
        JSValue *date = [JSValue valueWithObject:[NSDate dateWithTimeIntervalSince1970:86400] inContext:context];
        printf("date: %s, back %.0f\n", [[date invokeMethod:@"toISOString" withArguments:nil] toString].UTF8String,
               [[date toDate] timeIntervalSince1970]);
        printf("toInt32 of 2^32+5: %d, toUInt32 of -1: %u\n", [[context evaluateScript:@"4294967301"] toInt32],
               [[context evaluateScript:@"-1"] toUInt32]);

        /* blocks with rectangles, as Spectacle sets them up */
        context[@"CGRectContainsRect"] = ^BOOL(CGRect a, CGRect b) {
            return CGRectContainsRect(a, b);
        };
        context[@"CGRectGetMidX"] = ^CGFloat(CGRect r) {
            return CGRectGetMidX(r);
        };
        context[@"sum"] = ^int(int a, int b) {
            NSArray *args = [JSContext currentArguments];
            return a + b + (int)args.count * 100;
        };
        context[@"inset"] = ^CGRect(CGRect r, CGFloat by) {
            return CGRectInset(r, by, by);
        };
        printf("contains: %s, midX %s, sum %s\n",
               [[context evaluateScript:@"CGRectContainsRect({x:0,y:0,width:100,height:100},"
                                        @" {x:10,y:10,width:5,height:5})"] toString].UTF8String,
               [[context evaluateScript:@"CGRectGetMidX({x:10,y:0,width:50,height:1})"] toString].UTF8String,
               [[context evaluateScript:@"sum(1, 2)"] toString].UTF8String);
        printf("inset: %s\n",
               RectString([[context evaluateScript:@"inset({x:0,y:0,width:100,height:50}, 10)"] toRect]).UTF8String);

        /* an exported object keeping a JavaScript function */
        Registry *registry = [Registry new];
        context[@"registry"] = registry;
        [context evaluateScript:@"registry.registerCalculationWithAction(function (w, s) {"
                                @"  return {x: s.x, y: s.y, width: s.width / 2, height: s.height};"
                                @"}, 'LeftHalf');"
                                @"registry.title = 'Spectacle-like';"];
        JSValue *calc = registry.calculations[@"LeftHalf"];
        JSValue *result = [calc callWithArguments:@[
            [JSValue valueWithRect:CGRectMake(5, 5, 10, 10) inContext:context],
            [JSValue valueWithRect:CGRectMake(0, 0, 1440, 900) inContext:context]
        ]];
        printf("left half: %s, title %s, count %s\n", RectString([result toRect]).UTF8String,
               registry.title.UTF8String, [[context evaluateScript:@"registry.count"] toString].UTF8String);
        printf("describe: %s, add %s, same wrapper %s\n",
               [[context evaluateScript:@"registry.describeTimes('ab', 3)"] toString].UTF8String,
               [[context evaluateScript:@"registry.add(1.5, 2)"] toString].UTF8String,
               [[context evaluateScript:@"(function (r) { return r === registry; })"]
                   callWithArguments:@[ registry ]].toString.UTF8String);
        printf("back to ObjC: %s\n", [[context[@"registry"] toObject] isEqual:registry] ? "the same object" : "another");

        /* exceptions, to the handler */
        [context evaluateScript:@"throw new RangeError('too far')"];
        printf("handler: %s\n", lastError.UTF8String);
        [context evaluateScript:@"registry.noSuchMethod()"];
        printf("handler: %s\n", lastError.UTF8String);
        context.exceptionHandler = nil;
        [context evaluateScript:@"null.x"];
        printf("exception property: %s\n", [context.exception[@"name"] toString].UTF8String);
    }
    return 0;
}
