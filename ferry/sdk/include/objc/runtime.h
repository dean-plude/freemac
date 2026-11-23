/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Objective-C runtime's public functions. Written for freemac
 * from Apple's public documentation; not Apple's header. */
#ifndef _FERRY_OBJC_RUNTIME_H_
#define _FERRY_OBJC_RUNTIME_H_
#include <objc/objc.h>

typedef struct objc_method *Method;
typedef struct objc_ivar *Ivar;
typedef struct objc_category *Category;
typedef struct objc_property *objc_property_t;
#ifdef __OBJC__
@class Protocol;
#else
typedef struct objc_object Protocol;
#endif

struct objc_method_description { SEL name; char *types; };
typedef struct { const char *name; const char *value; } objc_property_attribute_t;

typedef uintptr_t objc_AssociationPolicy;
enum {
    OBJC_ASSOCIATION_ASSIGN = 0,
    OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1,
    OBJC_ASSOCIATION_COPY_NONATOMIC = 3,
    OBJC_ASSOCIATION_RETAIN = 01401,
    OBJC_ASSOCIATION_COPY = 01403,
};

__FERRY_BEGIN
id object_copy(id obj, size_t size) OBJC_ARC_UNAVAILABLE;
id object_dispose(id obj) OBJC_ARC_UNAVAILABLE;
Class object_getClass(id obj);
Class object_setClass(id obj, Class cls);
BOOL object_isClass(id obj);
id object_getIvar(id obj, Ivar ivar);
void object_setIvar(id obj, Ivar ivar, id value);
void object_setIvarWithStrongDefault(id obj, Ivar ivar, id value);

Class objc_getClass(const char *name);
Class objc_getMetaClass(const char *name);
Class objc_lookUpClass(const char *name);
Class objc_getRequiredClass(const char *name);
int objc_getClassList(Class *buffer, int count);
Class *objc_copyClassList(unsigned int *count);

const char *class_getName(Class cls);
BOOL class_isMetaClass(Class cls);
Class class_getSuperclass(Class cls);
int class_getVersion(Class cls);
void class_setVersion(Class cls, int version);
size_t class_getInstanceSize(Class cls);
Ivar class_getInstanceVariable(Class cls, const char *name);
Ivar class_getClassVariable(Class cls, const char *name);
Ivar *class_copyIvarList(Class cls, unsigned int *count);
Method class_getInstanceMethod(Class cls, SEL name);
Method class_getClassMethod(Class cls, SEL name);
IMP class_getMethodImplementation(Class cls, SEL name);
IMP class_getMethodImplementation_stret(Class cls, SEL name);
BOOL class_respondsToSelector(Class cls, SEL sel);
Method *class_copyMethodList(Class cls, unsigned int *count);
BOOL class_conformsToProtocol(Class cls, Protocol *protocol);
Protocol *__unsafe_unretained *class_copyProtocolList(Class cls, unsigned int *count);
objc_property_t class_getProperty(Class cls, const char *name);
objc_property_t *class_copyPropertyList(Class cls, unsigned int *count);
const uint8_t *class_getIvarLayout(Class cls);
const uint8_t *class_getWeakIvarLayout(Class cls);
BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);
IMP class_replaceMethod(Class cls, SEL name, IMP imp, const char *types);
BOOL class_addIvar(Class cls, const char *name, size_t size, uint8_t alignment, const char *types);
BOOL class_addProtocol(Class cls, Protocol *protocol);
BOOL class_addProperty(Class cls, const char *name, const objc_property_attribute_t *attributes,
                       unsigned int count);
const char *class_getImageName(Class cls);
id class_createInstance(Class cls, size_t extraBytes) OBJC_ARC_UNAVAILABLE;
id objc_constructInstance(Class cls, void *bytes) OBJC_ARC_UNAVAILABLE;
void *objc_destructInstance(id obj) OBJC_ARC_UNAVAILABLE;

Class objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes);
void objc_registerClassPair(Class cls);
void objc_disposeClassPair(Class cls);

SEL method_getName(Method m);
IMP method_getImplementation(Method m);
const char *method_getTypeEncoding(Method m);
unsigned int method_getNumberOfArguments(Method m);
char *method_copyReturnType(Method m);
char *method_copyArgumentType(Method m, unsigned int index);
void method_getReturnType(Method m, char *dst, size_t dst_len);
void method_getArgumentType(Method m, unsigned int index, char *dst, size_t dst_len);
struct objc_method_description *method_getDescription(Method m);
IMP method_setImplementation(Method m, IMP imp);
void method_exchangeImplementations(Method m1, Method m2);

const char *ivar_getName(Ivar v);
const char *ivar_getTypeEncoding(Ivar v);
ptrdiff_t ivar_getOffset(Ivar v);

const char *property_getName(objc_property_t property);
const char *property_getAttributes(objc_property_t property);
objc_property_attribute_t *property_copyAttributeList(objc_property_t property, unsigned int *count);
char *property_copyAttributeValue(objc_property_t property, const char *attributeName);

Protocol *objc_getProtocol(const char *name);
Protocol *__unsafe_unretained *objc_copyProtocolList(unsigned int *count);
BOOL protocol_conformsToProtocol(Protocol *proto, Protocol *other);
BOOL protocol_isEqual(Protocol *proto, Protocol *other);
const char *protocol_getName(Protocol *proto);
struct objc_method_description protocol_getMethodDescription(Protocol *proto, SEL aSel, BOOL isRequiredMethod,
                                                             BOOL isInstanceMethod);
struct objc_method_description *protocol_copyMethodDescriptionList(Protocol *proto, BOOL isRequiredMethod,
                                                                   BOOL isInstanceMethod, unsigned int *count);
objc_property_t *protocol_copyPropertyList(Protocol *proto, unsigned int *count);
Protocol *__unsafe_unretained *protocol_copyProtocolList(Protocol *proto, unsigned int *count);
Protocol *objc_allocateProtocol(const char *name);
void objc_registerProtocol(Protocol *proto);
void protocol_addMethodDescription(Protocol *proto, SEL name, const char *types, BOOL isRequiredMethod,
                                   BOOL isInstanceMethod);
void protocol_addProtocol(Protocol *proto, Protocol *addition);

IMP imp_implementationWithBlock(id block);
id imp_getBlock(IMP anImp);
BOOL imp_removeBlock(IMP anImp);

id objc_loadWeak(id *location);
id objc_storeWeak(id *location, id obj);

void objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy);
id objc_getAssociatedObject(id object, const void *key);
void objc_removeAssociatedObjects(id object);

void objc_enumerationMutation(id obj);
void objc_setEnumerationMutationHandler(void (*handler)(id));

/* exceptions */
typedef void (*objc_uncaught_exception_handler)(id exception);
typedef id (*objc_exception_preprocessor)(id exception);
void objc_exception_throw(id exception) __attribute__((noreturn));
void objc_exception_rethrow(void) __attribute__((noreturn));
objc_uncaught_exception_handler objc_setUncaughtExceptionHandler(objc_uncaught_exception_handler fn);
objc_exception_preprocessor objc_setExceptionPreprocessor(objc_exception_preprocessor fn);
void objc_terminate(void) __attribute__((noreturn));
__FERRY_END

#define _C_ID       '@'
#define _C_CLASS    '#'
#define _C_SEL      ':'
#define _C_CHR      'c'
#define _C_UCHR     'C'
#define _C_SHT      's'
#define _C_USHT     'S'
#define _C_INT      'i'
#define _C_UINT     'I'
#define _C_LNG      'l'
#define _C_ULNG     'L'
#define _C_LNG_LNG  'q'
#define _C_ULNG_LNG 'Q'
#define _C_FLT      'f'
#define _C_DBL      'd'
#define _C_BOOL     'B'
#define _C_VOID     'v'
#define _C_PTR      '^'
#define _C_CHARPTR  '*'
#define _C_STRUCT_B '{'
#define _C_STRUCT_E '}'
#endif
