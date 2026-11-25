/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The COM-style interfaces of CFPlugIn (freemac 1.NEXT, Ferry 0.NEXT),
 * written from Apple's public documentation of CFPlugIn: the IUnknown
 * functions every plug-in interface starts with, and their result codes. */
#ifndef _FERRY_CFPLUGINCOM_H_
#define _FERRY_CFPLUGINCOM_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef SInt32 HRESULT;
typedef UInt32 ULONG;
typedef void *LPVOID;
typedef CFUUIDBytes REFIID;

#define SUCCEEDED(r) ((HRESULT)(r) >= 0)
#define FAILED(r) ((HRESULT)(r) < 0)
#define S_OK ((HRESULT)0x00000000L)
#define S_FALSE ((HRESULT)0x00000001L)
#define E_UNEXPECTED ((HRESULT)0x8000FFFFL)
#define E_NOTIMPL ((HRESULT)0x80000001L)
#define E_OUTOFMEMORY ((HRESULT)0x80000002L)
#define E_INVALIDARG ((HRESULT)0x80000003L)
#define E_NOINTERFACE ((HRESULT)0x80000004L)
#define E_POINTER ((HRESULT)0x80000005L)
#define E_HANDLE ((HRESULT)0x80000006L)
#define E_ABORT ((HRESULT)0x80000007L)
#define E_FAIL ((HRESULT)0x80000008L)
#define E_ACCESSDENIED ((HRESULT)0x80000009L)

#define IUnknownUUID                                                                                      \
    CFUUIDGetConstantUUIDWithBytes(kCFAllocatorSystemDefault, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, \
                                   0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46)
#define IUNKNOWN_C_GUTS                                                         \
    void *_reserved;                                                            \
    HRESULT (*QueryInterface)(void *thisPointer, REFIID iid, LPVOID *ppv);      \
    ULONG (*AddRef)(void *thisPointer);                                         \
    ULONG (*Release)(void *thisPointer)
typedef struct IUnknownVTbl {
    IUNKNOWN_C_GUTS;
} IUnknownVTbl;
__FERRY_END
#endif
