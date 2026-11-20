/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * What Ferry's libobjc.A.dylib exports to Mac programs. The names are the C
 * names; Mach-O adds a leading underscore. Each entry's address is all the
 * loader needs, so the functions are declared here without their types.
 */
#include "../ferry.h"

/* Only addresses are needed here, so nothing is declared with its real type. */
struct fobjc_class;
extern char _objc_empty_cache_storage[];

#define OBJC_FUNCTIONS(X) \
    X(objc_msgSend, ferry_objc_msgSend) \
    X(objc_msgSend_stret, ferry_objc_msgSend_stret) \
    X(objc_msgSend_fpret, ferry_objc_msgSend_fpret) \
    X(objc_msgSend_fp2ret, ferry_objc_msgSend_fp2ret) \
    X(objc_msgSendSuper, ferry_objc_msgSendSuper) \
    X(objc_msgSendSuper2, ferry_objc_msgSendSuper2) \
    X(objc_msgSendSuper_stret, ferry_objc_msgSendSuper_stret) \
    X(objc_msgSendSuper2_stret, ferry_objc_msgSendSuper2_stret) \
    X(_objc_msgForward, ferry_objc_msgForward) \
    X(_objc_msgForward_stret, ferry_objc_msgForward_stret) \
    X(sel_registerName, sel_registerName) \
    X(sel_getUid, sel_getUid) \
    X(sel_getName, sel_getName) \
    X(sel_isEqual, sel_isEqual) \
    X(sel_isMapped, sel_isMapped) \
    X(objc_getClass, objc_getClass) \
    X(objc_lookUpClass, objc_lookUpClass) \
    X(objc_getRequiredClass, objc_getRequiredClass) \
    X(objc_getMetaClass, objc_getMetaClass) \
    X(objc_getClassList, objc_getClassList) \
    X(objc_copyClassList, objc_copyClassList) \
    X(objc_allocateClassPair, objc_allocateClassPair) \
    X(objc_registerClassPair, objc_registerClassPair) \
    X(objc_disposeClassPair, objc_disposeClassPair) \
    X(objc_duplicateClass, objc_duplicateClass) \
    X(objc_getProtocol, objc_getProtocol) \
    X(objc_copyProtocolList, objc_copyProtocolList) \
    X(objc_allocateProtocol, objc_allocateProtocol) \
    X(objc_registerProtocol, objc_registerProtocol) \
    X(class_getName, class_getName) \
    X(class_getSuperclass, class_getSuperclass) \
    X(class_isMetaClass, class_isMetaClass) \
    X(class_getInstanceSize, class_getInstanceSize) \
    X(class_getVersion, class_getVersion) \
    X(class_setVersion, class_setVersion) \
    X(class_getImageName, class_getImageName) \
    X(class_getIvarLayout, class_getIvarLayout) \
    X(class_getWeakIvarLayout, class_getWeakIvarLayout) \
    X(class_setIvarLayout, class_setIvarLayout) \
    X(class_setWeakIvarLayout, class_setWeakIvarLayout) \
    X(class_getInstanceMethod, class_getInstanceMethod) \
    X(class_getClassMethod, class_getClassMethod) \
    X(class_getMethodImplementation, class_getMethodImplementation) \
    X(class_getMethodImplementation_stret, class_getMethodImplementation_stret) \
    X(class_respondsToSelector, class_respondsToSelector) \
    X(class_copyMethodList, class_copyMethodList) \
    X(class_addMethod, class_addMethod) \
    X(class_replaceMethod, class_replaceMethod) \
    X(class_getInstanceVariable, class_getInstanceVariable) \
    X(class_getClassVariable, class_getClassVariable) \
    X(class_copyIvarList, class_copyIvarList) \
    X(class_addIvar, class_addIvar) \
    X(class_getProperty, class_getProperty) \
    X(class_copyPropertyList, class_copyPropertyList) \
    X(class_addProperty, class_addProperty) \
    X(class_conformsToProtocol, class_conformsToProtocol) \
    X(class_copyProtocolList, class_copyProtocolList) \
    X(class_addProtocol, class_addProtocol) \
    X(class_createInstance, class_createInstance) \
    X(objc_constructInstance, objc_constructInstance) \
    X(objc_destructInstance, objc_destructInstance) \
    X(object_dispose, object_dispose) \
    X(method_getName, method_getName) \
    X(method_getImplementation, method_getImplementation) \
    X(method_getTypeEncoding, method_getTypeEncoding) \
    X(method_setImplementation, method_setImplementation) \
    X(method_exchangeImplementations, method_exchangeImplementations) \
    X(method_getNumberOfArguments, method_getNumberOfArguments) \
    X(method_copyReturnType, method_copyReturnType) \
    X(method_copyArgumentType, method_copyArgumentType) \
    X(method_getReturnType, method_getReturnType) \
    X(method_getArgumentType, method_getArgumentType) \
    X(method_getDescription, method_getDescription) \
    X(ivar_getName, ivar_getName) \
    X(ivar_getTypeEncoding, ivar_getTypeEncoding) \
    X(ivar_getOffset, ivar_getOffset) \
    X(property_getName, property_getName) \
    X(property_getAttributes, property_getAttributes) \
    X(property_copyAttributeValue, property_copyAttributeValue) \
    X(property_copyAttributeList, property_copyAttributeList) \
    X(protocol_getName, protocol_getName) \
    X(protocol_isEqual, protocol_isEqual) \
    X(protocol_conformsToProtocol, protocol_conformsToProtocol) \
    X(protocol_copyProtocolList, protocol_copyProtocolList) \
    X(protocol_copyMethodDescriptionList, protocol_copyMethodDescriptionList) \
    X(protocol_getMethodDescription, protocol_getMethodDescription) \
    X(protocol_copyPropertyList, protocol_copyPropertyList) \
    X(protocol_addProtocol, protocol_addProtocol) \
    X(protocol_addMethodDescription, protocol_addMethodDescription) \
    X(object_getClass, object_getClass) \
    X(object_setClass, object_setClass) \
    X(object_getClassName, object_getClassName) \
    X(object_isClass, object_isClass) \
    X(object_getIvar, object_getIvar) \
    X(object_setIvar, object_setIvar) \
    X(object_setIvarWithStrongDefault, object_setIvarWithStrongDefault) \
    X(objc_retain, objc_retain) \
    X(objc_release, objc_release) \
    X(objc_autorelease, objc_autorelease) \
    X(objc_autoreleaseReturnValue, objc_autoreleaseReturnValue) \
    X(objc_retainAutoreleasedReturnValue, objc_retainAutoreleasedReturnValue) \
    X(objc_claimAutoreleasedReturnValue, objc_claimAutoreleasedReturnValue) \
    X(objc_unsafeClaimAutoreleasedReturnValue, objc_unsafeClaimAutoreleasedReturnValue) \
    X(objc_retainAutorelease, objc_retainAutorelease) \
    X(objc_retainAutoreleaseReturnValue, objc_retainAutoreleaseReturnValue) \
    X(objc_retainedObject, objc_retainedObject) \
    X(objc_unretainedObject, objc_unretainedObject) \
    X(objc_unretainedPointer, objc_unretainedPointer) \
    X(objc_retainBlock, objc_retainBlock) \
    X(objc_storeStrong, objc_storeStrong) \
    X(objc_autoreleasePoolPush, objc_autoreleasePoolPush) \
    X(objc_autoreleasePoolPop, objc_autoreleasePoolPop) \
    X(_objc_autoreleasePoolPush, objc_autoreleasePoolPush) \
    X(_objc_autoreleasePoolPop, objc_autoreleasePoolPop) \
    X(_objc_autoreleasePoolPrint, _objc_autoreleasePoolPrint) \
    X(objc_storeWeak, objc_storeWeak) \
    X(objc_storeWeakOrNil, objc_storeWeakOrNil) \
    X(objc_initWeak, objc_initWeak) \
    X(objc_initWeakOrNil, objc_initWeakOrNil) \
    X(objc_destroyWeak, objc_destroyWeak) \
    X(objc_loadWeak, objc_loadWeak) \
    X(objc_loadWeakRetained, objc_loadWeakRetained) \
    X(objc_copyWeak, objc_copyWeak) \
    X(objc_moveWeak, objc_moveWeak) \
    X(objc_setAssociatedObject, objc_setAssociatedObject) \
    X(objc_getAssociatedObject, objc_getAssociatedObject) \
    X(objc_removeAssociatedObjects, objc_removeAssociatedObjects) \
    X(objc_sync_enter, objc_sync_enter) \
    X(objc_sync_exit, objc_sync_exit) \
    X(objc_getProperty, objc_getProperty) \
    X(objc_setProperty, objc_setProperty) \
    X(objc_setProperty_atomic, objc_setProperty_atomic) \
    X(objc_setProperty_nonatomic, objc_setProperty_nonatomic) \
    X(objc_setProperty_atomic_copy, objc_setProperty_atomic_copy) \
    X(objc_setProperty_nonatomic_copy, objc_setProperty_nonatomic_copy) \
    X(objc_copyStruct, objc_copyStruct) \
    X(objc_copyCppObjectAtomic, objc_copyCppObjectAtomic) \
    X(objc_alloc, objc_alloc) \
    X(objc_allocWithZone, objc_allocWithZone) \
    X(objc_alloc_init, objc_alloc_init) \
    X(objc_opt_new, objc_opt_new) \
    X(objc_opt_self, objc_opt_self) \
    X(objc_opt_class, objc_opt_class) \
    X(objc_opt_isKindOfClass, objc_opt_isKindOfClass) \
    X(objc_opt_respondsToSelector, objc_opt_respondsToSelector) \
    X(objc_enumerationMutation, objc_enumerationMutation) \
    X(objc_setEnumerationMutationHandler, objc_setEnumerationMutationHandler) \
    X(objc_exception_throw, objc_exception_throw) \
    X(objc_exception_rethrow, objc_exception_rethrow) \
    X(objc_begin_catch, objc_begin_catch) \
    X(objc_end_catch, objc_end_catch) \
    X(objc_terminate, objc_terminate) \
    X(__objc_personality_v0, ferry_objc_personality) \
    X(imp_implementationWithBlock, imp_implementationWithBlock) \
    X(imp_getBlock, imp_getBlock) \
    X(imp_removeBlock, imp_removeBlock)

#define DECLARE(name, impl) void impl(void);
OBJC_FUNCTIONS(DECLARE)

extern struct fobjc_class ferry_class_NSObject, ferry_meta_NSObject, ferry_class_Protocol, ferry_meta_Protocol;
extern struct fobjc_class ferry_block_NSBlock, ferry_meta_NSBlock;

#define ENTRY(name, impl) {#name, (void *)impl},
const struct ferry_symbol ferry_objc_symbols[] = {
    OBJC_FUNCTIONS(ENTRY)
    {"OBJC_CLASS_$_NSObject", &ferry_class_NSObject},
    {"OBJC_METACLASS_$_NSObject", &ferry_meta_NSObject},
    {"OBJC_CLASS_$_Protocol", &ferry_class_Protocol},
    {"OBJC_METACLASS_$_Protocol", &ferry_meta_Protocol},
    {"_objc_empty_cache", _objc_empty_cache_storage},
    {NULL, NULL},
};
