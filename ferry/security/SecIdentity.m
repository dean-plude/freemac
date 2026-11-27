/* SPDX-License-Identifier: GPL-3.0-or-later
 * More of Security (freemac 1.265, Ferry 0.88.0; first seen in Obsidian,
 * where Chromium asks for these as it starts), from Apple's public
 * documentation of SecIdentity, SecKeychain, SecPolicy, SecCertificate and
 * SecTrustSettings:
 *
 * - Identities (a certificate with its private key, for client sign-in):
 *   Ferry keeps none, so a search finds nothing and there is no preferred
 *   identity. Chromium then offers no client certificate, as on a Mac
 *   whose keychain holds none.
 * - Keychain callbacks: accepted; Ferry's keychain reports no events.
 * - Trust settings: none are set, in any domain, so the system's trusted
 *   roots (which Ferry reads from this system's certificate store) decide.
 * - Type IDs for certificates, policies and trust, so CFGetTypeID can tell
 *   them apart, and a policy's properties.
 */
#import "SInternal.h"

#define FERRY_TYPE_SECCERTIFICATE 0x46520044
#define FERRY_TYPE_SECPOLICY 0x46520045
#define FERRY_TYPE_SECTRUST 0x46520046
#define FERRY_TYPE_SECIDENTITY 0x46520047
#define FERRY_TYPE_SECIDENTITYSEARCH 0x46520048

@implementation SCertificate (FerryType)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_SECCERTIFICATE; }
@end
@implementation SPolicy (FerryType)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_SECPOLICY; }
@end
@implementation STrust (FerryType)
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_SECTRUST; }
@end

S_EXPORT CFTypeID SecCertificateGetTypeID(void) { return FERRY_TYPE_SECCERTIFICATE; }
S_EXPORT CFTypeID SecPolicyGetTypeID(void) { return FERRY_TYPE_SECPOLICY; }
S_EXPORT CFTypeID SecTrustGetTypeID(void) { return FERRY_TYPE_SECTRUST; }
S_EXPORT CFTypeID SecIdentityGetTypeID(void) { return FERRY_TYPE_SECIDENTITY; }
S_EXPORT CFTypeID SecIdentitySearchGetTypeID(void) { return FERRY_TYPE_SECIDENTITYSEARCH; }

/* ---- policies' properties ----------------------------------------------------------- */

S_EXPORT const CFStringRef kSecPolicyOid = (CFStringRef)@"SecPolicyOid";
S_EXPORT const CFStringRef kSecPolicyName = (CFStringRef)@"SecPolicyName";
S_EXPORT const CFStringRef kSecPolicyClient = (CFStringRef)@"SecPolicyClient";
S_EXPORT const CFStringRef kSecPolicyRevocationFlags = (CFStringRef)@"SecPolicyRevocationFlags";
S_EXPORT const CFStringRef kSecPolicyTeamIdentifier = (CFStringRef)@"SecPolicyTeamIdentifier";
/* the policies' object identifiers, as published for X.509 policies */
S_EXPORT const CFStringRef kSecPolicyAppleX509Basic = (CFStringRef)@"1.2.840.113635.100.1.2";
S_EXPORT const CFStringRef kSecPolicyAppleSSL = (CFStringRef)@"1.2.840.113635.100.1.3";

S_EXPORT CFDictionaryRef SecPolicyCopyProperties(SecPolicyRef policyRef)
{
    SPolicy *p = (SPolicy *)policyRef;
    if (![p isKindOfClass:[SPolicy class]])
        return NULL;
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    d[(NSString *)kSecPolicyOid] = (NSString *)(p->ssl ? kSecPolicyAppleSSL : kSecPolicyAppleX509Basic);
    if (p->ssl) {
        if (p->host.length)
            d[(NSString *)kSecPolicyName] = p->host;
        if (!p->server)
            d[(NSString *)kSecPolicyClient] = (id)kCFBooleanTrue;
    }
    return (CFDictionaryRef)d;
}

/* ---- identities: Ferry keeps none ---------------------------------------------------- */

@interface SIdentitySearch : NSObject
@end
@implementation SIdentitySearch
- (CFTypeID)_ferryCFTypeID { return FERRY_TYPE_SECIDENTITYSEARCH; }
@end



S_EXPORT OSStatus SecIdentitySearchCreate(CFTypeRef keychainOrArray, uint32_t keyUsage, SecIdentitySearchRef *searchRef)
{
    if (!searchRef)
        return errSecParam;
    *searchRef = (SecIdentitySearchRef)[[SIdentitySearch alloc] init];
    return errSecSuccess;
}

S_EXPORT OSStatus SecIdentitySearchCopyNext(SecIdentitySearchRef searchRef, SecIdentityRef *identity)
{
    if (identity)
        *identity = NULL;
    return searchRef ? errSecItemNotFound : errSecParam;
}

S_EXPORT SecIdentityRef SecIdentityCopyPreferred(CFStringRef name, CFArrayRef keyUsage, CFArrayRef validIssuers)
{
    return NULL;
}

S_EXPORT OSStatus SecIdentityCopyPreference(CFStringRef name, uint32_t keyUsage, CFArrayRef validIssuers,
                                            SecIdentityRef *identity)
{
    if (identity)
        *identity = NULL;
    return errSecItemNotFound;
}

S_EXPORT OSStatus SecIdentitySetPreferred(SecIdentityRef identity, CFStringRef name, CFArrayRef keyUsage)
{
    return errSecUnimplemented;
}

S_EXPORT OSStatus SecIdentityCreateWithCertificate(CFTypeRef keychainOrArray, SecCertificateRef certificateRef,
                                                   SecIdentityRef *identityRef)
{
    if (identityRef)
        *identityRef = NULL;
    return errSecItemNotFound;
}

/* there are no identities, so whatever is passed isn't one */
S_EXPORT OSStatus SecIdentityCopyCertificate(SecIdentityRef identityRef, SecCertificateRef *certificateRef)
{
    if (certificateRef)
        *certificateRef = NULL;
    return errSecParam;
}

S_EXPORT OSStatus SecIdentityCopyPrivateKey(SecIdentityRef identityRef, SecKeyRef *privateKeyRef)
{
    if (privateKeyRef)
        *privateKeyRef = NULL;
    return errSecParam;
}

/* ---- keychain callbacks ------------------------------------------------------------------ */



S_EXPORT OSStatus SecKeychainAddCallback(SecKeychainCallback callbackFunction, uint32_t eventMask, void *userContext)
{
    return callbackFunction ? errSecSuccess : errSecInvalidCallback;
}

S_EXPORT OSStatus SecKeychainRemoveCallback(SecKeychainCallback callbackFunction)
{
    return errSecSuccess;
}

/* ---- trust settings: none are set ---------------------------------------------------- */

S_EXPORT OSStatus SecTrustSettingsCopyCertificates(uint32_t domain, CFArrayRef *certArray)
{
    if (certArray)
        *certArray = NULL;
    return errSecNoTrustSettings;
}

S_EXPORT OSStatus SecTrustSettingsCopyTrustSettings(SecCertificateRef certRef, uint32_t domain, CFArrayRef *trustSettings)
{
    if (trustSettings)
        *trustSettings = NULL;
    return errSecItemNotFound;
}

S_EXPORT OSStatus SecTrustSettingsCopyModificationDate(SecCertificateRef certRef, uint32_t domain, CFDateRef *modificationDate)
{
    if (modificationDate)
        *modificationDate = NULL;
    return errSecItemNotFound;
}

S_EXPORT OSStatus SecTrustSettingsSetTrustSettings(SecCertificateRef certRef, uint32_t domain, CFTypeRef trustSettingsDictOrArray)
{
    return errSecUnimplemented;
}
