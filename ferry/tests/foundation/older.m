/* SPDX-License-Identifier: GPL-3.0-or-later
 * The older Foundation and CoreServices names Sequel Pro and SPMySQL use
 * (freemac 1.226, Ferry 0.50.0): NSCalendarDate, the scripting execution
 * context, NSConnection within one program, CFXML's entity calls, the
 * DriverServices clock, and object_getInstanceVariable; and mutable
 * collections read from files. */
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#import <objc/runtime.h>
#include <mach/mach_time.h>
#include <unistd.h>

@interface Holder : NSObject {
  @public
    NSString *name;
    void *raw;
}
@end
@implementation Holder
@end

@interface Root : NSObject
- (NSString *)greet:(NSString *)who;
@end
@implementation Root
- (NSString *)greet:(NSString *)who { return [@"hello " stringByAppendingString:who]; }
@end

static void calendar_dates(void)
{
    printf("NSCalendarDate:\n");
    NSTimeZone *gmt = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSTimeZone *plus2 = [NSTimeZone timeZoneForSecondsFromGMT:7200];
    NSCalendarDate *d = [NSCalendarDate dateWithYear:2024 month:2 day:29 hour:13 minute:5 second:9 timeZone:gmt];
    printf("  is a date: %d, since 2001: %.0f\n", [d isKindOfClass:[NSDate class]], [d timeIntervalSinceReferenceDate]);
    printf("  %s\n", [[d description] UTF8String]);
    printf("  %s\n", [[d descriptionWithCalendarFormat:@"%A %e %B %Y, %I:%M %p, day %j, weekday %w"] UTF8String]);
    printf("  fields: %ld-%ld-%ld %ld:%ld:%ld, week day %ld, year day %ld\n", (long)[d yearOfCommonEra],
           (long)[d monthOfYear], (long)[d dayOfMonth], (long)[d hourOfDay], (long)[d minuteOfHour],
           (long)[d secondOfMinute], (long)[d dayOfWeek], (long)[d dayOfYear]);
    [d setTimeZone:plus2];
    printf("  in +0200: %s\n", [[d description] UTF8String]);
    NSCalendarDate *later = [d dateByAddingYears:1 months:0 days:0 hours:0 minutes:0 seconds:0];
    printf("  a year on (from 29 February): %s\n", [[later descriptionWithCalendarFormat:@"%Y-%m-%d"] UTF8String]);
    NSCalendarDate *month = [d dateByAddingYears:0 months:-1 days:2 hours:3 minutes:0 seconds:0];
    printf("  a month back, two days and three hours on: %s\n", [[month description] UTF8String]);
    NSInteger y, mo, dd, h, mi, s;
    [later years:&y months:&mo days:&dd hours:&h minutes:&mi seconds:&s sinceDate:d];
    printf("  difference: %ldy %ldm %ldd %ldh %ldm %lds\n", (long)y, (long)mo, (long)dd, (long)h, (long)mi, (long)s);
    [d years:NULL months:NULL days:&dd hours:&h minutes:NULL seconds:NULL sinceDate:later];
    printf("  backwards in days and hours: %ldd %ldh\n", (long)dd, (long)h);

    NSCalendarDate *p = [NSCalendarDate dateWithString:@"2010-07-04 18:30:00 -0500"
                                        calendarFormat:@"%Y-%m-%d %H:%M:%S %z"];
    printf("  parsed: %s (%.0f)\n", [[p description] UTF8String], [p timeIntervalSinceReferenceDate]);
    NSCalendarDate *q = [[NSCalendarDate alloc] initWithString:@"Mar 3 99 7:04 PM GMT"
                                                calendarFormat:@"%b %d %y %I:%M %p %Z"];
    printf("  parsed: %s\n", [[q descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M %Z"] UTF8String]);
    [q release];
    printf("  not a date: %s\n", [NSCalendarDate dateWithString:@"soon" calendarFormat:@"%Y"] ? "a date" : "nil");
    NSCalendarDate *copy = [[p copy] autorelease];
    printf("  copy: %s, equal %d\n", [[copy description] UTF8String], [copy isEqualToDate:p]);
    NSDate *plain = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
    printf("  from NSDate: %s\n", [[plain descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S.%F %Z" timeZone:gmt
                                                                  locale:nil] UTF8String]);
}

static void scripting_and_connections(void)
{
    printf("NSScriptExecutionContext:\n");
    NSScriptExecutionContext *c = [NSScriptExecutionContext sharedScriptExecutionContext];
    [c setTopLevelObject:@"the app"];
    printf("  shared: %d, top level %s\n", c == [NSScriptExecutionContext sharedScriptExecutionContext],
           [[[NSScriptExecutionContext sharedScriptExecutionContext] topLevelObject] UTF8String]);

    printf("NSConnection:\n");
    Root *root = [[[Root alloc] init] autorelease];
    NSConnection *served = [NSConnection new];
    [served runInNewThread];
    [served removeRunLoop:[NSRunLoop currentRunLoop]];
    [served setRootObject:root];
    printf("  registered: %d\n", [served registerName:@"org.example.older"]);
    NSConnection *other = [[NSConnection new] autorelease];
    printf("  same name again: %d\n", [other registerName:@"org.example.older"]);
    id proxy = [NSConnection rootProxyForConnectionWithRegisteredName:@"org.example.older" host:nil];
    printf("  root proxy: %s\n", [[proxy greet:@"tunnel"] UTF8String]);
    printf("  unknown name: %s\n",
           [NSConnection rootProxyForConnectionWithRegisteredName:@"org.example.none" host:nil] ? "found" : "nil");
    [served invalidate];
    printf("  after invalidate: valid %d, found %d\n", [served isValid],
           [NSConnection rootProxyForConnectionWithRegisteredName:@"org.example.older" host:nil] != nil);
    [served release];
}

static void xml_entities(void)
{
    printf("CFXML entities:\n");
    CFStringRef e = CFXMLCreateStringByEscapingEntities(NULL, CFSTR("a < b & \"c\" > 'd'"), NULL);
    printf("  escaped: %s\n", [(NSString *)e UTF8String]);
    CFStringRef u = CFXMLCreateStringByUnescapingEntities(NULL, e, NULL);
    printf("  back: %s\n", [(NSString *)u UTF8String]);
    NSDictionary *more = @{@"copy" : @"(c)"};
    CFStringRef v = CFXMLCreateStringByUnescapingEntities(
        NULL, CFSTR("&copy; &#65;&#x42; &unknown; &amp"), (CFDictionaryRef)more);
    printf("  more: %s\n", [(NSString *)v UTF8String]);
    CFRelease(e);
    CFRelease(u);
    CFRelease(v);
}

static unsigned long long wide(UnsignedWide w) { return ((unsigned long long)w.hi << 32) | w.lo; }

static void driver_services(void)
{
    printf("DriverServices:\n");
    AbsoluteTime a = UpTime();
    usleep(20000);
    AbsoluteTime b = UpTime();
    Nanoseconds ns = AbsoluteDeltaToNanoseconds(b, a);
    printf("  20 ms apart: %d\n", wide(ns) >= 20000000ull && wide(ns) < 2000000000ull);
    printf("  same as mach_absolute_time's count: %d\n", wide(AbsoluteToNanoseconds(a)) <= mach_absolute_time());
    printf("  durations: %d ms, %d (microseconds when negative)\n",
           (int)NanosecondsToDuration(DurationToNanoseconds(1500)),
           (int)NanosecondsToDuration(DurationToNanoseconds(-250)));
    AbsoluteTime later = AddDurationToAbsolute(2 * durationSecond, a);
    printf("  two seconds on: %d ms\n", (int)AbsoluteDeltaToDuration(later, a));
    printf("  forever: %d\n", NanosecondsToDuration(DurationToNanoseconds(durationForever)) == durationForever);
}

static void instance_variables(void)
{
    printf("object_getInstanceVariable:\n");
    Holder *h = [[Holder alloc] init];
    h->name = @"first";
    void *value = NULL;
    Ivar iv = object_getInstanceVariable(h, "name", &value);
    printf("  %s = %s\n", ivar_getName(iv), [(NSString *)value UTF8String]);
    object_setInstanceVariable(h, "raw", (void *)0x1234);
    printf("  raw = %p\n", h->raw);
    printf("  missing: %s\n", object_getInstanceVariable(h, "nothing", &value) ? "found" : "NULL");
    [h release];
}

static void mutable_from_files(void)
{
    printf("mutable collections from files:\n");
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-older-test.plist"];
    [@{@"a" : @1} writeToFile:path atomically:YES];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    d[@"b"] = @2;
    printf("  dictionary: %lu keys, mutable %d\n", (unsigned long)[d count],
           [d isKindOfClass:[NSMutableDictionary class]]);
    [@[ @"x" ] writeToFile:path atomically:YES];
    NSMutableArray *a = [NSMutableArray arrayWithContentsOfFile:path];
    [a addObject:@"y"];
    printf("  array: %s\n", [[a componentsJoinedByString:@" "] UTF8String]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

int main(void)
{
    @autoreleasepool {
        calendar_dates();
        scripting_and_connections();
        xml_entities();
        driver_services();
        instance_variables();
        mutable_from_files();
    }
    return 0;
}
