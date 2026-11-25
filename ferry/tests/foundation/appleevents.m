/* Ferry test: Core Services' Apple events, as Flycut and other apps use
 * them: descriptors, coercions, lists and records, object specifiers and
 * the comparison, logical and range descriptors, an event sent to the
 * program's own handler with its reply, an event to another program, and
 * Launch Services' answers for applications that aren't there. Foundation
 * brings in Core Services, as on a Mac. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static const char *four(OSType t)
{
    static char buf[4][8];
    static int at;
    char *b = buf[at++ % 4];
    for (int i = 0; i < 4; i++)
        b[i] = (char)(t >> (24 - 8 * i));
    b[4] = 0;
    return b;
}

static OSErr echo(const AppleEvent *ev, AppleEvent *reply, SRefCon refcon)
{
    char text[64] = {0};
    DescType got = 0;
    Size size = 0;
    OSErr e = AEGetParamPtr(ev, keyDirectObject, typeUTF8Text, &got, text, sizeof text - 1, &size);
    AppleEvent current;
    AEGetTheCurrentEvent(&current);
    printf("handler: refcon %ld, direct object %s (%d) \"%s\", it is the current event %d\n", (long)refcon,
           four(got), e, text, current.dataHandle == ev->dataHandle);
    char upper[64] = {0};
    for (Size i = 0; i < size; i++)
        upper[i] = (char)(text[i] >= 'a' && text[i] <= 'z' ? text[i] - 32 : text[i]);
    AEPutParamPtr(reply, keyDirectObject, typeUTF8Text, upper, size);
    return noErr;
}

static OSErr refuse(const AppleEvent *ev, AppleEvent *reply, SRefCon refcon) { return errAEEventNotHandled; }
static OSErr fail(const AppleEvent *ev, AppleEvent *reply, SRefCon refcon) { return -1728; /* errAENoSuchObject */ }

static void descriptors(void)
{
    AEDesc d;
    AEInitializeDesc(&d);
    printf("initialized: %s\n", four(d.descriptorType));
    SInt32 n = 42;
    printf("create: %d type %s size %ld\n", AECreateDesc(typeSInt32, &n, sizeof n, &d), four(d.descriptorType),
           (long)AEGetDescDataSize(&d));
    AEDesc text;
    printf("coerce long to utf8: %d\n", AECoerceDesc(&d, typeUTF8Text, &text));
    char buf[16] = {0};
    AEGetDescData(&text, buf, sizeof buf - 1);
    printf("  \"%s\"\n", buf);
    AEDesc back;
    printf("coerce it back: %d", AECoerceDesc(&text, typeSInt32, &back));
    SInt32 m = 0;
    AEGetDescData(&back, &m, sizeof m);
    printf(" %d\n", (int)m);
    AEDesc dup;
    AEDuplicateDesc(&d, &dup);
    printf("duplicate: %s, a record %d\n", four(dup.descriptorType), AECheckIsRecord(&dup));
    AEDisposeDesc(&d);
    AEDisposeDesc(&dup);
    AEDisposeDesc(&text);
    AEDisposeDesc(&back);
    printf("disposed: %s\n", four(d.descriptorType));

    AEDescList list;
    AECreateList(NULL, 0, false, &list);
    AEPutPtr(&list, 0, typeUTF8Text, "one", 3);
    AEPutPtr(&list, 0, typeUTF8Text, "two", 3);
    SInt32 three = 3;
    AEPutPtr(&list, 0, typeSInt32, &three, sizeof three);
    long count = 0;
    AECountItems(&list, &count);
    printf("list: %ld items, type %s\n", count, four(list.descriptorType));
    DescType t;
    Size sz;
    AESizeOfNthItem(&list, 2, &t, &sz);
    printf("item 2: %s size %ld\n", four(t), (long)sz);
    printf("item 9: %d\n", AEGetNthPtr(&list, 9, typeWildCard, NULL, &t, buf, sizeof buf, &sz));
    AEDeleteItem(&list, 1);
    AECountItems(&list, &count);
    printf("after a delete: %ld\n", count);
    AEDisposeDesc(&list);

    AERecord rec;
    AECreateList(NULL, 0, true, &rec);
    AEPutKeyPtr(&rec, 'name', typeUTF8Text, "Flycut", 6);
    AEPutKeyPtr(&rec, 'size', typeSInt32, &three, sizeof three);
    printf("record: a record %d\n", AECheckIsRecord(&rec));
    memset(buf, 0, sizeof buf);
    printf("key name: %d", AEGetKeyPtr(&rec, 'name', typeUTF8Text, &t, buf, sizeof buf - 1, &sz));
    printf(" \"%s\"\n", buf);
    printf("missing key: %d\n", AEGetKeyPtr(&rec, 'none', typeWildCard, &t, buf, sizeof buf, &sz));
    AEDeleteKeyDesc(&rec, 'name');
    AECountItems(&rec, &count);
    printf("after deleting a key: %ld\n", count);
    AEDisposeDesc(&rec);
}

static void specifiers(void)
{
    AEDesc app, index, spec, name, byname;
    AEInitializeDesc(&app); /* the application: the null container */
    CreateOffsetDescriptor(2, &index);
    printf("offset: %s\n", four(index.descriptorType));
    printf("specifier: %d", CreateObjSpecifier(cWindow, &app, formAbsolutePosition, &index, true, &spec));
    printf(" type %s, index disposed %d\n", four(spec.descriptorType), index.descriptorType == typeNull);
    DescType t;
    Size sz;
    DescType want = 0, form = 0;
    AEGetKeyPtr(&spec, keyAEDesiredClass, typeType, &t, &want, sizeof want, &sz);
    AEGetKeyPtr(&spec, keyAEKeyForm, typeEnumerated, &t, &form, sizeof form, &sz);
    AEDesc from;
    AEGetKeyDesc(&spec, keyAEContainer, typeWildCard, &from);
    SInt32 seld = 0;
    AEGetKeyPtr(&spec, keyAEKeyData, typeSInt32, &t, &seld, sizeof seld, &sz);
    printf("  want %s from %s form %s seld %d\n", four(want), four(from.descriptorType), four(form), (int)seld);
    AEDisposeDesc(&from);

    AECreateDesc(typeUTF8Text, "Clippings", 9, &name);
    CreateObjSpecifier(cDocument, &spec, formName, &name, false, &byname);
    AEGetKeyDesc(&byname, keyAEContainer, typeWildCard, &from);
    printf("nested: container %s, name kept %s\n", four(from.descriptorType), four(name.descriptorType));
    AEDisposeDesc(&from);

    AEDesc a, b, cmp, terms, logical, range;
    SInt32 one = 1, two = 2;
    AECreateDesc(typeSInt32, &one, sizeof one, &a);
    AECreateDesc(typeSInt32, &two, sizeof two, &b);
    CreateCompDescriptor(kAEEquals, &a, &b, false, &cmp);
    printf("comparison: %s", four(cmp.descriptorType));
    DescType op = 0;
    AEGetKeyPtr(&cmp, keyAECompOperator, typeEnumerated, &t, &op, sizeof op, &sz);
    printf(" operator %s\n", four(op));
    AECreateList(NULL, 0, false, &terms);
    AEPutDesc(&terms, 0, &cmp);
    AEPutDesc(&terms, 0, &cmp);
    CreateLogicalDescriptor(&terms, kAEAND, true, &logical);
    AEDesc got;
    AEGetKeyDesc(&logical, keyAELogicalTerms, typeAEList, &got);
    long count = 0;
    AECountItems(&got, &count);
    printf("logical: %s with %ld terms\n", four(logical.descriptorType), count);
    AEDisposeDesc(&got);
    CreateRangeDescriptor(&a, &b, true, &range);
    printf("range: %s, inputs disposed %d\n", four(range.descriptorType), a.descriptorType == typeNull);
    AEDisposeDesc(&cmp);
    AEDisposeDesc(&logical);
    AEDisposeDesc(&range);
    AEDisposeDesc(&name);
    AEDisposeDesc(&byname);
    AEDisposeDesc(&spec);
}

static void events(void)
{
    printf("install: %d\n", AEInstallEventHandler('Test', 'echo', echo, (SRefCon)7, false));
    AEInstallEventHandler('Test', 'deny', refuse, 0, false);
    AEInstallEventHandler('Test', 'fail', fail, 0, false);
    AEEventHandlerUPP proc = NULL;
    SRefCon refcon = 0;
    printf("get handler: %d, the same %d refcon %ld\n", AEGetEventHandler('Test', 'echo', &proc, &refcon, false),
           proc == echo, (long)refcon);

    ProcessSerialNumber me = {0, kCurrentProcess};
    AEAddressDesc target;
    AECreateDesc(typeProcessSerialNumber, &me, sizeof me, &target);
    AppleEvent ev, reply;
    printf("create event: %d", AECreateAppleEvent('Test', 'echo', &target, kAutoGenerateReturnID, kAnyTransactionID,
                                                    &ev));
    printf(" type %s\n", four(ev.descriptorType));
    AEPutParamPtr(&ev, keyDirectObject, typeUTF8Text, "clip", 4);
    AEEventClass cls = 0;
    DescType t;
    Size sz;
    AEGetAttributePtr(&ev, keyEventClassAttr, typeType, &t, &cls, sizeof cls, &sz);
    printf("its class: %s\n", four(cls));
    printf("send to itself: %d\n", (int)AESendMessage(&ev, &reply, kAEWaitReply, kAEDefaultTimeout));
    char buf[16] = {0};
    printf("reply: %d", AEGetParamPtr(&reply, keyDirectObject, typeUTF8Text, &t, buf, sizeof buf - 1, &sz));
    printf(" \"%s\"\n", buf);
    AEDisposeDesc(&reply);
    AEDisposeDesc(&ev);

    AECreateAppleEvent('Test', 'deny', &target, kAutoGenerateReturnID, kAnyTransactionID, &ev);
    printf("a handler that declines: %d\n", (int)AESendMessage(&ev, &reply, kAEWaitReply, kAEDefaultTimeout));
    AEDisposeDesc(&ev);
    AEDisposeDesc(&reply);
    AECreateAppleEvent('Test', 'fail', &target, kAutoGenerateReturnID, kAnyTransactionID, &ev);
    printf("a handler that fails: %d", (int)AESendMessage(&ev, &reply, kAEWaitReply, kAEDefaultTimeout));
    SInt32 err = 0;
    AEGetParamPtr(&reply, keyErrorNumber, typeSInt32, &t, &err, sizeof err, &sz);
    printf(", its reply's error %d\n", (int)err);
    AEDisposeDesc(&ev);
    AEDisposeDesc(&reply);
    AECreateAppleEvent('Test', 'none', &target, kAutoGenerateReturnID, kAnyTransactionID, &ev);
    printf("no handler: %d\n", (int)AESendMessage(&ev, &reply, kAEWaitReply, kAEDefaultTimeout));
    AEDisposeDesc(&ev);
    AEDisposeDesc(&target);

    pid_t pid = getpid();
    AECreateDesc(typeKernelProcessID, &pid, sizeof pid, &target);
    AECreateAppleEvent('Test', 'echo', &target, kAutoGenerateReturnID, kAnyTransactionID, &ev);
    AEPutParamPtr(&ev, keyDirectObject, typeUTF8Text, "pid", 3);
    printf("send by pid: %d\n", (int)AESendMessage(&ev, NULL, kAENoReply, kAEDefaultTimeout));
    AEDisposeDesc(&ev);
    AEDisposeDesc(&target);

    AECreateDesc(typeApplicationBundleID, "com.example.elsewhere", 21, &target);
    AECreateAppleEvent(kCoreEventClass, kAEOpenDocuments, &target, kAutoGenerateReturnID, kAnyTransactionID, &ev);
    printf("send to another program: %d\n", (int)AESendMessage(&ev, &reply, kAEWaitReply, kAEDefaultTimeout));
    printf("permission for it: %d\n",
           (int)AEDeterminePermissionToAutomateTarget(&target, kCoreEventClass, kAEOpenDocuments, false));
    AEDisposeDesc(&ev);
    AEDisposeDesc(&target);
    printf("remove: %d, again %d\n", AERemoveEventHandler('Test', 'echo', echo, false),
           AERemoveEventHandler('Test', 'echo', echo, false));
}

static void launch_services(void)
{
    CFURLRef url = NULL;
    printf("find an app that isn't there: %d\n",
           (int)LSFindApplicationForInfo(kLSUnknownCreator, CFSTR("com.example.not-installed"), NULL, NULL, &url));
    CFErrorRef error = NULL;
    CFArrayRef apps = LSCopyApplicationURLsForBundleIdentifier(CFSTR("com.example.not-installed"), &error);
    printf("its URLs: %s, error %ld\n", apps ? "some" : "none", error ? (long)CFErrorGetCode(error) : 0L);
    if (error)
        CFRelease(error);
    printf("default handler for a scheme nothing handles: %s\n",
           LSCopyDefaultHandlerForURLScheme(CFSTR("x-ferry-none")) ? "some" : "none");
    printf("set one: %d\n", (int)LSSetDefaultHandlerForURLScheme(CFSTR("x-ferry-none"), CFSTR("com.example.app")));
}

int main(void)
{
    @autoreleasepool {
        descriptors();
        specifiers();
        events();
        launch_services();
    }
    return 0;
}
