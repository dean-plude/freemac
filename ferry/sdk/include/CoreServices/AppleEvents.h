/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Apple Event Manager's descriptors, written from Apple's
 * public "Apple Event Manager Reference". Descriptors, lists, records and
 * Apple events are built, read, coerced between the common types and
 * disposed of as on a Mac, so code that builds an event and reads its reply
 * runs. No other program on freemac receives Apple events, so sending one
 * to another program answers procNotFound (and an empty reply), and the
 * handlers an app installs are kept but never called. Served from
 * Foundation's file, as CoreServices is. */
#ifndef _FERRY_CORESERVICES_APPLEEVENTS_H_
#define _FERRY_CORESERVICES_APPLEEVENTS_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef int16_t OSErr;
typedef int32_t OSStatus;
typedef uint32_t OSType;
typedef ResType DescType;
typedef FourCharCode AEKeyword;
typedef FourCharCode AEEventClass;
typedef FourCharCode AEEventID;
typedef int16_t AEReturnID;
typedef int32_t AETransactionID;
typedef int32_t AESendMode;
typedef int16_t AESendPriority;
typedef int8_t AEEventSource;

typedef struct OpaqueAEDataStorageType *AEDataStorageType;
typedef AEDataStorageType *AEDataStorage;
typedef struct AEDesc {
    DescType descriptorType;
    AEDataStorage dataHandle;
} AEDesc;
typedef AEDesc *AEDescPtr;
typedef AEDesc AEAddressDesc;
typedef AEDesc AEDescList;
typedef AEDescList AERecord;
typedef AERecord AppleEvent;
typedef AppleEvent *AppleEventPtr;
typedef struct AEKeyDesc {
    AEKeyword descKey;
    AEDesc descContent;
} AEKeyDesc;

/* descriptor types (AEDataModel.h) */
enum {
    typeBoolean = 'bool', typeChar = 'TEXT', typeSInt16 = 'shor', typeSInt32 = 'long', typeUInt16 = 'ushr',
    typeUInt32 = 'magn', typeSInt64 = 'comp', typeUInt64 = 'ucom', typeIEEE32BitFloatingPoint = 'sing',
    typeIEEE64BitFloatingPoint = 'doub', type128BitFloatingPoint = 'ldbl', typeDecimalStruct = 'decm',
    typeAEList = 'list', typeAERecord = 'reco', typeAppleEvent = 'aevt', typeEventRecord = 'evrc',
    typeTrue = 'true', typeFalse = 'fals', typeAlias = 'alis', typeEnumerated = 'enum', typeType = 'type',
    typeAppParameters = 'appa', typeProperty = 'prop', typeFSRef = 'fsrf', typeFileURL = 'furl',
    typeBookmarkData = 'bmrk', typeKeyword = 'keyw', typeSectionH = 'sect', typeWildCard = '****',
    typeApplSignature = 'sign', typeQDRectangle = 'qdrt', typeFixed = 'fixd', typeProcessSerialNumber = 'psn ',
    typeApplicationURL = 'aprl', typeNull = 'null', typeKernelProcessID = 'kpid', typeMachPort = 'port',
    typeApplicationBundleID = 'bund', typeUnicodeText = 'utxt', typeStyledUnicodeText = 'sutx',
    typeUTF8Text = 'utf8', typeUTF16ExternalRepresentation = 'ut16', typeEncodedString = 'encs',
    typeCString = 'cstr', typePString = 'pstr', typeLongDateTime = 'ldt ', typeData = 'tdta',
    typeObjectSpecifier = 'obj ', typeAbsoluteOrdinal = 'abso', typeIntlText = 'itxt', typeStyledText = 'STXT',
    typeSMInt = typeSInt16, typeShortInteger = typeSInt16, typeInteger = typeSInt32, typeLongInteger = typeSInt32,
    typeMagnitude = typeUInt32, typeComp = typeSInt64, typeSMFloat = typeIEEE32BitFloatingPoint,
    typeShortFloat = typeIEEE32BitFloatingPoint, typeFloat = typeIEEE64BitFloatingPoint,
    typeLongFloat = typeIEEE64BitFloatingPoint,
};

/* keys and attributes (AEDataModel.h, AppleEvents.h) */
enum {
    keyDirectObject = '----', keyErrorNumber = 'errn', keyErrorString = 'errs', keyProcessSerialNumber = 'psn ',
    keyPreDispatch = 'phac', keySelectProc = 'selh', keyAERecorderCount = 'recr', keyAEVersion = 'vers',
    keyTransactionIDAttr = 'tran', keyReturnIDAttr = 'rtid', keyEventClassAttr = 'evcl', keyEventIDAttr = 'evid',
    keyAddressAttr = 'addr', keyOptionalKeywordAttr = 'optk', keyTimeoutAttr = 'timo', keyInteractLevelAttr = 'inte',
    keyEventSourceAttr = 'esrc', keyMissedKeywordAttr = 'miss', keyOriginalAddressAttr = 'from',
    keyAcceptTimeoutAttr = 'actm', keyReplyRequestedAttr = 'repq', keySenderEUIDAttr = 'seid',
    keySenderEGIDAttr = 'sgid', keySenderUIDAttr = 'uids', keySenderGIDAttr = 'gids', keySenderPIDAttr = 'spid',
    keySenderAuditTokenAttr = 'tokn',
};

/* the object model's keys, forms and classes the apps name (AEObjects.h, AERegistry.h) */
enum {
    keyAEDesiredClass = 'want', keyAEContainer = 'from', keyAEKeyForm = 'form', keyAEKeyData = 'seld',
    keyAEPosition = 'kpos', keyAEPropData = 'prdt', keyAEObjectClass = 'kocl', keyAEInsertHere = 'insh',
    keyAEObject = 'kobj', keyAEData = 'data', keyAEParamFlags = 'pmfg', keyAEResult = '----',
    formAbsolutePosition = 'indx', formRelativePosition = 'rele', formTest = 'test', formRange = 'rang',
    formPropertyID = 'prop', formName = 'name', formUniqueID = 'ID  ', formDirect = 'dire',
    kAEFirst = 'firs', kAELast = 'last', kAEMiddle = 'midd', kAEAny = 'any ', kAEAll = 'all ',
    kAENext = 'next', kAEPrevious = 'prev', kAEBefore = 'befo', kAEAfter = 'afte', kAEBeginning = 'bgng',
    kAEEnd = 'end ', kAEReplace = 'rplc',
    kAECoreSuite = 'core', kAEMiscStandards = 'misc', kCoreEventClass = 'aevt', kAERequiredSuite = 'reqd',
    kAEGetData = 'getd', kAESetData = 'setd', kAECreateElement = 'crel', kAEDelete = 'delo', kAEClone = 'clon',
    kAEMove = 'move', kAECountElements = 'cnte', kAEDoObjectsExist = 'doex', kAEOpen = 'odoc',
    kAEOpenApplication = 'oapp', kAEReopenApplication = 'rapp', kAEOpenDocuments = 'odoc',
    kAEPrintDocuments = 'pdoc', kAEOpenContents = 'ocon', kAEQuitApplication = 'quit', kAEAnswer = 'ansr',
    kAEApplicationDied = 'obit', kAEShowPreferences = 'pref', kAEGetURL = 'GURL', kInternetEventClass = 'GURL',
    pProperties = 'pALL', pName = 'pnam', pClass = 'pcls', pID = 'ID  ', pIndex = 'pidx', pContents = 'pcnt',
    cProperty = 'prop', cObject = 'cobj', cApplication = 'capp', cWindow = 'cwin', cDocument = 'docu',
    cFile = 'file', cText = 'ctxt', cInsertionLoc = 'insl', typeInsertionLoc = 'insl',
};

/* send modes, priorities and timeouts (AppleEvents.h) */
enum {
    kAENoReply = 0x00000001, kAEQueueReply = 0x00000002, kAEWaitReply = 0x00000003,
    kAEDontReconnect = 0x00000080, kAEWantReceipt = 0x00000200, kAENeverInteract = 0x00000010,
    kAECanInteract = 0x00000020, kAEAlwaysInteract = 0x00000030, kAECanSwitchLayer = 0x00000040,
    kAEDontRecord = 0x00001000, kAEDontExecute = 0x00002000, kAEProcessNonReplyEvents = 0x00008000,
    kAEDoNotAutomaticallyAddAnnotationsToEvent = 0x00010000,
};
enum { kAENormalPriority = 0, kAEHighPriority = 1 };
enum { kAEDefaultTimeout = -1, kNoTimeOut = -2 };
enum { kAutoGenerateReturnID = -1, kAnyTransactionID = 0 };
enum { kAEInteractWithSelf = 0, kAEInteractWithLocal = 1, kAEInteractWithAll = 2 };

/* result codes (MacErrors.h) */
enum {
    errAECoercionFail = -1700, errAEDescNotFound = -1701, errAECorruptData = -1702, errAEWrongDataType = -1703,
    errAENotAEDesc = -1704, errAEBadListItem = -1705, errAENewerVersion = -1706, errAENotAppleEvent = -1707,
    errAEEventNotHandled = -1708, errAEReplyNotValid = -1709, errAEUnknownSendMode = -1710,
    errAEWaitCanceled = -1711, errAETimeout = -1712, errAENoUserInteraction = -1713,
    errAENotASpecialFunction = -1714, errAEParamMissed = -1715, errAEUnknownAddressType = -1716,
    errAEHandlerNotFound = -1717, errAEReplyNotArrived = -1718, errAEIllegalIndex = -1719,
    errAEEventNotPermitted = -1743, errAEEventWouldRequireUserConsent = -1744,
    connectionInvalid = -609, noPortErr = -903,
};
#ifndef _FERRY_PROCNOTFOUND
#define _FERRY_PROCNOTFOUND
enum { procNotFound = -600 };
#endif

typedef OSErr (*AEEventHandlerProcPtr)(const AppleEvent *theAppleEvent, AppleEvent *reply, void *handlerRefcon);
typedef AEEventHandlerProcPtr AEEventHandlerUPP;
typedef OSErr (*AECoerceDescProcPtr)(const AEDesc *fromDesc, DescType toType, void *handlerRefcon, AEDesc *toDesc);
typedef AECoerceDescProcPtr AECoercionHandlerUPP;

/* descriptors */
void AEInitializeDesc(AEDesc *desc);
OSErr AECreateDesc(DescType typeCode, const void *dataPtr, Size dataSize, AEDesc *result);
OSErr AEDisposeDesc(AEDesc *theAEDesc);
OSErr AEDuplicateDesc(const AEDesc *theAEDesc, AEDesc *result);
Size AEGetDescDataSize(const AEDesc *theAEDesc);
OSErr AEGetDescData(const AEDesc *theAEDesc, void *dataPtr, Size maximumSize);
OSErr AEReplaceDescData(DescType typeCode, const void *dataPtr, Size dataSize, AEDesc *theAEDesc);
OSErr AECoercePtr(DescType typeCode, const void *dataPtr, Size dataSize, DescType toType, AEDesc *result);
OSErr AECoerceDesc(const AEDesc *theAEDesc, DescType toType, AEDesc *result);
Boolean AECheckIsRecord(const AEDesc *theDesc);

/* lists */
OSErr AECreateList(const void *factoringPtr, Size factoredSize, Boolean isRecord, AEDescList *resultList);
OSErr AECountItems(const AEDescList *theAEDescList, long *theCount);
OSErr AEPutPtr(AEDescList *theAEDescList, long index, DescType typeCode, const void *dataPtr, Size dataSize);
OSErr AEPutDesc(AEDescList *theAEDescList, long index, const AEDesc *theAEDesc);
OSErr AEGetNthPtr(const AEDescList *theAEDescList, long index, DescType desiredType, AEKeyword *theAEKeyword,
                  DescType *typeCode, void *dataPtr, Size maximumSize, Size *actualSize);
OSErr AEGetNthDesc(const AEDescList *theAEDescList, long index, DescType desiredType, AEKeyword *theAEKeyword,
                   AEDesc *result);
OSErr AESizeOfNthItem(const AEDescList *theAEDescList, long index, DescType *typeCode, Size *dataSize);
OSErr AEDeleteItem(AEDescList *theAEDescList, long index);

/* records */
OSErr AEPutKeyPtr(AERecord *theAERecord, AEKeyword theAEKeyword, DescType typeCode, const void *dataPtr,
                  Size dataSize);
OSErr AEPutKeyDesc(AERecord *theAERecord, AEKeyword theAEKeyword, const AEDesc *theAEDesc);
OSErr AEGetKeyPtr(const AERecord *theAERecord, AEKeyword theAEKeyword, DescType desiredType, DescType *typeCode,
                  void *dataPtr, Size maximumSize, Size *actualSize);
OSErr AEGetKeyDesc(const AERecord *theAERecord, AEKeyword theAEKeyword, DescType desiredType, AEDesc *result);
OSErr AESizeOfKeyDesc(const AERecord *theAERecord, AEKeyword theAEKeyword, DescType *typeCode, Size *dataSize);
OSErr AEDeleteKeyDesc(AERecord *theAERecord, AEKeyword theAEKeyword);

/* Apple events */
OSErr AECreateAppleEvent(AEEventClass theAEEventClass, AEEventID theAEEventID, const AEAddressDesc *target,
                         AEReturnID returnID, AETransactionID transactionID, AppleEvent *result);
OSErr AEPutParamPtr(AppleEvent *theAppleEvent, AEKeyword theAEKeyword, DescType typeCode, const void *dataPtr,
                    Size dataSize);
OSErr AEPutParamDesc(AppleEvent *theAppleEvent, AEKeyword theAEKeyword, const AEDesc *theAEDesc);
OSErr AEGetParamPtr(const AppleEvent *theAppleEvent, AEKeyword theAEKeyword, DescType desiredType,
                    DescType *actualType, void *dataPtr, Size maximumSize, Size *actualSize);
OSErr AEGetParamDesc(const AppleEvent *theAppleEvent, AEKeyword theAEKeyword, DescType desiredType, AEDesc *result);
OSErr AESizeOfParam(const AppleEvent *theAppleEvent, AEKeyword theAEKeyword, DescType *typeCode, Size *dataSize);
OSErr AEDeleteParam(AppleEvent *theAppleEvent, AEKeyword theAEKeyword);
OSErr AEGetAttributePtr(const AppleEvent *theAppleEvent, AEKeyword theAEKeyword, DescType desiredType,
                        DescType *typeCode, void *dataPtr, Size maximumSize, Size *actualSize);
OSErr AEGetAttributeDesc(const AppleEvent *theAppleEvent, AEKeyword theAEKeyword, DescType desiredType,
                         AEDesc *result);
OSErr AESizeOfAttribute(const AppleEvent *theAppleEvent, AEKeyword theAEKeyword, DescType *typeCode, Size *dataSize);
OSErr AEPutAttributePtr(AppleEvent *theAppleEvent, AEKeyword theAEKeyword, DescType typeCode, const void *dataPtr,
                        Size dataSize);
OSErr AEPutAttributeDesc(AppleEvent *theAppleEvent, AEKeyword theAEKeyword, const AEDesc *theAEDesc);

/* object specifiers and the descriptors inside them (AEObjects.h): records
 * of their own types, as on a Mac */
enum {
    typeCompDescriptor = 'cmpd', typeLogicalDescriptor = 'logi', typeRangeDescriptor = 'rang',
    keyAECompOperator = 'relo', keyAEObject1 = 'obj1', keyAEObject2 = 'obj2', keyAELogicalOperator = 'logc',
    keyAELogicalTerms = 'term', keyAERangeStart = 'star', keyAERangeStop = 'stop',
    /* comparison and logical operators */
    kAEGreaterThan = '>   ', kAEGreaterThanEquals = '>=  ', kAEEquals = '=   ', kAELessThan = '<   ',
    kAELessThanEquals = '<=  ', kAEBeginsWith = 'bgwt', kAEEndsWith = 'ends', kAEContains = 'cont',
    kAEAND = 'AND ', kAEOR = 'OR  ', kAENOT = 'NOT ',
};
OSErr CreateObjSpecifier(DescType desiredClass, AEDesc *theContainer, DescType keyForm, AEDesc *keyData,
                         Boolean disposeInputs, AEDesc *objSpecifier);
OSErr CreateOffsetDescriptor(long theOffset, AEDesc *theDescriptor);
OSErr CreateCompDescriptor(DescType comparisonOperator, AEDesc *operand1, AEDesc *operand2, Boolean disposeInputs,
                           AEDesc *theDescriptor);
OSErr CreateLogicalDescriptor(AEDescList *theLogicalTerms, DescType theLogicOperator, Boolean disposeInputs,
                              AEDesc *theDescriptor);
OSErr CreateRangeDescriptor(AEDesc *rangeStart, AEDesc *rangeStop, Boolean disposeInputs, AEDesc *theDescriptor);

/* sending: no other program here receives Apple events */
OSStatus AESendMessage(const AppleEvent *event, AppleEvent *reply, AESendMode sendMode, long timeOutInTicks);
OSErr AESend(const AppleEvent *theAppleEvent, AppleEvent *reply, AESendMode sendMode, AESendPriority sendPriority,
             long timeOutInTicks, void *idleProc, void *filterProc);
OSErr AEInstallEventHandler(AEEventClass theAEEventClass, AEEventID theAEEventID, AEEventHandlerUPP handler,
                            void *handlerRefcon, Boolean isSysHandler);
OSErr AERemoveEventHandler(AEEventClass theAEEventClass, AEEventID theAEEventID, AEEventHandlerUPP handler,
                           Boolean isSysHandler);
OSErr AEGetEventHandler(AEEventClass theAEEventClass, AEEventID theAEEventID, AEEventHandlerUPP *handler,
                        void **handlerRefcon, Boolean isSysHandler);
OSErr AEGetTheCurrentEvent(AppleEvent *theAppleEvent);
OSStatus AEDeterminePermissionToAutomateTarget(const AEAddressDesc *target, AEEventClass theAEEventClass,
                                               AEEventID theAEEventID, Boolean askUserIfNeeded);
#define NewAEEventHandlerUPP(p) ((AEEventHandlerUPP)(p))
#define DisposeAEEventHandlerUPP(u) ((void)(u))
__FERRY_END
#endif
