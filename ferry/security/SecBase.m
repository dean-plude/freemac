/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Security framework: error messages and random bytes. Our own
 * code, written from Apple's public API documentation of Security
 * (SecBase.h and SecRandom.h); the messages follow the descriptions of each
 * status in that documentation, in Ferry's wording. */
#include "SInternal.h"
#include <stdio.h>
#include <stdlib.h>

S_EXPORT const SecRandomRef kSecRandomDefault = NULL;

S_EXPORT int SecRandomCopyBytes(SecRandomRef rnd, size_t count, void *bytes)
{
    if (count && !bytes)
        return errSecParam;
    return CCRandomGenerateBytes(bytes, count) == kCCSuccess ? errSecSuccess : errSecInternalComponent;
}

static const struct message {
    OSStatus status;
    const char *text;
} messages[] = {
    {errSecSuccess, "No error."},
    {errSecUnimplemented, "Function or operation not implemented."},
    {errSecDiskFull, "The disk is full."},
    {errSecIO, "An input/output error occurred."},
    {errSecOpWr, "The file is already open with write permission."},
    {errSecParam, "One or more parameters passed to a function were not valid."},
    {errSecWrPerm, "Write permissions error."},
    {errSecAllocate, "Failed to allocate memory."},
    {errSecUserCanceled, "User canceled the operation."},
    {errSecBadReq, "Bad parameter or invalid state for operation."},
    {errSecInternalComponent, "An internal component failed."},
    {errSecNotAvailable, "No keychain is available."},
    {errSecReadOnly, "This keychain cannot be modified."},
    {errSecAuthFailed, "The user name or passphrase you entered is not correct."},
    {errSecNoSuchKeychain, "The specified keychain could not be found."},
    {errSecInvalidKeychain, "The specified keychain is not a valid keychain file."},
    {errSecDuplicateKeychain, "A keychain with the same name already exists."},
    {errSecDuplicateItem, "The specified item already exists in the keychain."},
    {errSecItemNotFound, "The specified item could not be found in the keychain."},
    {errSecBufferTooSmall, "There is not enough memory available to use the specified item."},
    {errSecDataTooLarge, "This item contains information which is too large or in a format that cannot be displayed."},
    {errSecNoSuchAttr, "The specified attribute does not exist."},
    {errSecInvalidItemRef, "The specified item is no longer valid. It may have been deleted from the keychain."},
    {errSecInvalidSearchRef, "Unable to search the current keychain."},
    {errSecNoSuchClass, "The specified item does not appear to be a valid keychain item."},
    {errSecNoDefaultKeychain, "A default keychain could not be found."},
    {errSecInteractionNotAllowed, "User interaction is not allowed."},
    {errSecReadOnlyAttr, "The specified attribute could not be modified."},
    {errSecCreateChainFailed, "One or more certificates required to validate this certificate cannot be found."},
    {errSecNoAccessForItem, "The specified item has no access control."},
    {errSecUnsupportedFormat, "The specified import or export format is not supported."},
    {errSecUnknownFormat, "The item you are trying to import has an unknown format."},
    {errSecDecode, "Unable to decode the provided data."},
    {errSecMissingEntitlement, "A required entitlement isn't present."},
    {errSecHostNameMismatch, "The host name does not match the certificate."},
    {errSecCertificateExpired, "The certificate has expired."},
    {errSecCertificateNotValidYet, "The certificate is not yet valid."},
    {errSecNotTrusted, "The certificate is not trusted."},
    {errSecCSUnimplemented, "Code signing: this operation is not implemented."},
    {errSecCSInvalidObjectRef, "Code signing: invalid code object reference."},
    {errSecCSInvalidFlags, "Code signing: invalid flags."},
    {errSecCSObjectRequired, "Code signing: a required code object was not given."},
    {errSecCSStaticCodeNotFound, "Code signing: the code could not be found at the given path."},
    {errSecCSUnsupportedGuestAttributes, "Code signing: unsupported guest attributes."},
    {errSecCSNoSuchCode, "Code signing: no code matches the given attributes."},
    {errSecCSUnsigned, "Code signing: the code object is not signed at all."},
    {errSecCSSignatureFailed, "Code signing: the signature is not valid."},
    {errSecCSSignatureNotVerifiable, "Code signing: the signature cannot be verified."},
    {errSecCSReqInvalid, "Code signing: the requirement text is not valid."},
    {errSecCSReqUnsupported, "Code signing: the requirement is not supported."},
    {errSecCSReqFailed, "Code signing: the code does not satisfy the requirement."},
    {errSecCSInternalError, "Code signing: an internal error occurred."},
};

static const char *message_for(OSStatus status)
{
    for (size_t i = 0; i < sizeof messages / sizeof messages[0]; i++)
        if (messages[i].status == status)
            return messages[i].text;
    return NULL;
}

S_EXPORT CFStringRef SecCopyErrorMessageString(OSStatus status, void *reserved)
{
    const char *m = message_for(status);
    return m ? (CFStringRef)[[NSString alloc] initWithUTF8String:m] : NULL;
}

NSError *SCopyError(OSStatus status, NSString *detail)
{
    const char *m = message_for(status);
    NSString *text = detail ?: (m ? [NSString stringWithUTF8String:m] : [NSString stringWithFormat:@"OSStatus %d", (int)status]);
    return [[NSError alloc] initWithDomain:NSOSStatusErrorDomain code:status
                                  userInfo:[NSDictionary dictionaryWithObject:text forKey:NSLocalizedDescriptionKey]];
}

void SVerboseOnce(NSString *message)
{
    static NSMutableSet *said;
    const char *v = getenv("FERRY_VERBOSE");
    if (!v || !*v)
        return;
    @synchronized([SItem class]) {
        if (!said)
            said = [[NSMutableSet alloc] init];
        if ([said containsObject:message])
            return;
        [said addObject:message];
    }
    fflush(stdout);
    fprintf(stderr, "Ferry: Security: %s\n", [message UTF8String]);
}

BOOL SIsTrue(id value)
{
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}
