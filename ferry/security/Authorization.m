/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Security framework: authorization (freemac 1.223, Ferry 0.47.0).
 * Our own code, written from Apple's public documentation of
 * Authorization.h. Ferry never runs a program's code as another user, so
 * an authorization holds no rights: it can be made, passed around in its
 * external form and freed, and every ask for a right, or to run a tool
 * with privileges, answers errAuthorizationDenied. A program that asks
 * only when it must (Sparkle, for an app the user can't write to) carries
 * on with what it can do as the user. */
#include "SInternal.h"
#include <stdlib.h>
#include <string.h>

struct AuthorizationOpaqueRef {
    uint32_t magic;
    uint32_t serial;
};
#define AUTH_MAGIC 0x46524175 /* "FRAu" */

static BOOL valid(AuthorizationRef a) { return a && a->magic == AUTH_MAGIC; }

static OSStatus deny(const char *what)
{
    SVerboseOnce([NSString stringWithFormat:@"%s: Ferry doesn't run anything with another user's rights", what]);
    return errAuthorizationDenied;
}

/* Rights asked for here: only "none" is granted, so a call with no rights succeeds. */
static BOOL asks_for_rights(const AuthorizationRights *rights) { return rights && rights->count > 0; }

S_EXPORT OSStatus AuthorizationCreate(const AuthorizationRights *rights, const AuthorizationEnvironment *environment,
                                      AuthorizationFlags flags, AuthorizationRef *authorization)
{
    if (asks_for_rights(rights) && !(flags & kAuthorizationFlagPartialRights))
        return deny("AuthorizationCreate");
    if (!authorization)
        return errAuthorizationSuccess;
    static uint32_t serial;
    struct AuthorizationOpaqueRef *a = calloc(1, sizeof *a);
    if (!a)
        return errAuthorizationInternal;
    a->magic = AUTH_MAGIC;
    a->serial = __atomic_add_fetch(&serial, 1, __ATOMIC_RELAXED);
    *authorization = a;
    return errAuthorizationSuccess;
}

S_EXPORT OSStatus AuthorizationFree(AuthorizationRef authorization, AuthorizationFlags flags)
{
    if (!valid(authorization))
        return errAuthorizationInvalidRef;
    ((struct AuthorizationOpaqueRef *)authorization)->magic = 0;
    free((void *)authorization);
    return errAuthorizationSuccess;
}

S_EXPORT OSStatus AuthorizationCopyRights(AuthorizationRef authorization, const AuthorizationRights *rights,
                                          const AuthorizationEnvironment *environment, AuthorizationFlags flags,
                                          AuthorizationRights **authorizedRights)
{
    if (authorizedRights)
        *authorizedRights = NULL;
    if (!valid(authorization))
        return errAuthorizationInvalidRef;
    if (!asks_for_rights(rights)) {
        if (authorizedRights)
            *authorizedRights = calloc(1, sizeof(AuthorizationRights));
        return errAuthorizationSuccess;
    }
    if (flags & kAuthorizationFlagPartialRights) { /* none of them, which partial rights allows */
        if (authorizedRights)
            *authorizedRights = calloc(1, sizeof(AuthorizationRights));
        return errAuthorizationSuccess;
    }
    return deny(rights->items && rights->items[0].name ? rights->items[0].name : "AuthorizationCopyRights");
}

S_EXPORT void AuthorizationCopyRightsAsync(AuthorizationRef authorization, const AuthorizationRights *rights,
                                           const AuthorizationEnvironment *environment, AuthorizationFlags flags,
                                           void (^callbackBlock)(OSStatus err, AuthorizationRights *blockAuthorizedRights))
{
    AuthorizationRights *granted = NULL;
    OSStatus status = AuthorizationCopyRights(authorization, rights, environment, flags, &granted);
    void (^block)(OSStatus, AuthorizationRights *) = [callbackBlock copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        block(status, granted);
        [block release];
    });
}

S_EXPORT OSStatus AuthorizationCopyInfo(AuthorizationRef authorization, AuthorizationString tag,
                                        AuthorizationItemSet **info)
{
    if (!valid(authorization))
        return errAuthorizationInvalidRef;
    if (!info)
        return errAuthorizationInvalidPointer;
    *info = calloc(1, sizeof(AuthorizationItemSet));
    return *info ? errAuthorizationSuccess : errAuthorizationInternal;
}

S_EXPORT OSStatus AuthorizationMakeExternalForm(AuthorizationRef authorization, AuthorizationExternalForm *extForm)
{
    if (!valid(authorization))
        return errAuthorizationInvalidRef;
    if (!extForm)
        return errAuthorizationInvalidPointer;
    memset(extForm, 0, sizeof *extForm);
    memcpy(extForm->bytes, "ferry-authorization", 19);
    memcpy(extForm->bytes + 24, &authorization->serial, sizeof authorization->serial);
    return errAuthorizationSuccess;
}

S_EXPORT OSStatus AuthorizationCreateFromExternalForm(const AuthorizationExternalForm *extForm,
                                                      AuthorizationRef *authorization)
{
    if (!extForm || !authorization)
        return errAuthorizationInvalidPointer;
    if (memcmp(extForm->bytes, "ferry-authorization", 19))
        return errAuthorizationInvalidRef;
    return AuthorizationCreate(NULL, NULL, kAuthorizationFlagDefaults, authorization);
}

S_EXPORT OSStatus AuthorizationFreeItemSet(AuthorizationItemSet *set)
{
    if (!set)
        return errAuthorizationInvalidSet;
    free(set); /* the sets made here have no items of their own */
    return errAuthorizationSuccess;
}

S_EXPORT OSStatus AuthorizationExecuteWithPrivileges(AuthorizationRef authorization, const char *pathToTool,
                                                     AuthorizationFlags options, char *const *arguments,
                                                     FILE **communicationsPipe)
{
    if (communicationsPipe)
        *communicationsPipe = NULL;
    if (!valid(authorization))
        return errAuthorizationInvalidRef;
    return deny("AuthorizationExecuteWithPrivileges");
}

S_EXPORT OSStatus AuthorizationCopyPrivilegedReference(AuthorizationRef *authorization, AuthorizationFlags flags)
{
    if (authorization)
        *authorization = NULL;
    return errAuthorizationDenied;
}

/* the rights database, which holds none (freemac 1.224, Ferry 0.48.0) */
S_EXPORT OSStatus AuthorizationRightGet(const char *rightName, CFDictionaryRef *rightDefinition)
{
    if (rightDefinition)
        *rightDefinition = NULL;
    return errAuthorizationDenied;
}

S_EXPORT OSStatus AuthorizationRightSet(AuthorizationRef authorization, const char *rightName,
                                        CFTypeRef rightDefinition, CFStringRef descriptionKey, CFBundleRef bundle,
                                        CFStringRef localeTableName)
{
    if (!valid(authorization))
        return errAuthorizationInvalidRef;
    return deny("AuthorizationRightSet");
}

S_EXPORT OSStatus AuthorizationRightRemove(AuthorizationRef authorization, const char *rightName)
{
    if (!valid(authorization))
        return errAuthorizationInvalidRef;
    return deny("AuthorizationRightRemove");
}
