// SPDX-License-Identifier: GPL-3.0-or-later
// CommonCrypto's digests, HMAC, PBKDF2 and random bytes against published
// test vectors: RFC 1321 (MD5), FIPS 180-4's examples (SHA-1 and SHA-2),
// RFC 2202 and RFC 4231 (HMAC), RFC 6070 and RFC 7914 (PBKDF2). Each
// incremental form must agree with the one-shot call however the data is
// split.
#include <CommonCrypto/CommonCrypto.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void hex(const char *label, const unsigned char *p, size_t n)
{
    printf("%s ", label);
    for (size_t i = 0; i < n; i++)
        printf("%02x", p[i]);
    printf("\n");
}

static void unhex(const char *s, unsigned char *out, size_t *n)
{
    *n = 0;
    for (; s[0] && s[1]; s += 2) {
        unsigned v;
        sscanf(s, "%2x", &v);
        out[(*n)++] = (unsigned char)v;
    }
}

typedef unsigned char *(*OneShot)(const void *, CC_LONG, unsigned char *);
static const struct {
    const char *name;
    OneShot fn;
    size_t size;
} digests[] = {
    {"md5", CC_MD5, CC_MD5_DIGEST_LENGTH},          {"sha1", CC_SHA1, CC_SHA1_DIGEST_LENGTH},
    {"sha224", CC_SHA224, CC_SHA224_DIGEST_LENGTH}, {"sha256", CC_SHA256, CC_SHA256_DIGEST_LENGTH},
    {"sha384", CC_SHA384, CC_SHA384_DIGEST_LENGTH}, {"sha512", CC_SHA512, CC_SHA512_DIGEST_LENGTH},
};

// The same data through _Init, _Update in pieces of `step` bytes, and _Final.
static void incremental(int which, const unsigned char *data, size_t len, size_t step, unsigned char *md)
{
#define RUN(T, init, update, final)                         \
    {                                                       \
        T c;                                                \
        init(&c);                                           \
        for (size_t i = 0; i < len; i += step)              \
            update(&c, data + i, (CC_LONG)(len - i < step ? len - i : step)); \
        final(md, &c);                                      \
        return;                                             \
    }
    switch (which) {
    case 0: RUN(CC_MD5_CTX, CC_MD5_Init, CC_MD5_Update, CC_MD5_Final)
    case 1: RUN(CC_SHA1_CTX, CC_SHA1_Init, CC_SHA1_Update, CC_SHA1_Final)
    case 2: RUN(CC_SHA256_CTX, CC_SHA224_Init, CC_SHA224_Update, CC_SHA224_Final)
    case 3: RUN(CC_SHA256_CTX, CC_SHA256_Init, CC_SHA256_Update, CC_SHA256_Final)
    case 4: RUN(CC_SHA512_CTX, CC_SHA384_Init, CC_SHA384_Update, CC_SHA384_Final)
    case 5: RUN(CC_SHA512_CTX, CC_SHA512_Init, CC_SHA512_Update, CC_SHA512_Final)
    }
#undef RUN
}

int main(void)
{
    printf("context sizes: md5 %zu sha1 %zu sha256 %zu sha512 %zu hmac %zu\n", sizeof(CC_MD5_CTX),
           sizeof(CC_SHA1_CTX), sizeof(CC_SHA256_CTX), sizeof(CC_SHA512_CTX), sizeof(CCHmacContext));

    // RFC 1321, appendix A.5
    const char *md5_suite[] = {"", "a", "abc", "message digest", "abcdefghijklmnopqrstuvwxyz",
                               "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
                               "12345678901234567890123456789012345678901234567890123456789012345678901234567890"};
    unsigned char md[64];
    for (int i = 0; i < 7; i++) {
        char label[100];
        snprintf(label, sizeof label, "md5(\"%.20s%s\")", md5_suite[i], strlen(md5_suite[i]) > 20 ? "..." : "");
        hex(label, CC_MD5(md5_suite[i], (CC_LONG)strlen(md5_suite[i]), md), 16);
    }

    // FIPS 180-4's examples: "abc", the empty message, the two-block
    // messages, and a million 'a's (fed in pieces of 1000)
    const char *two_block = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    const char *two_block_512 = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklm"
                                "nopqrlmnopqrsmnopqrstnopqrstu";
    unsigned char *million = malloc(1000000);
    memset(million, 'a', 1000000);
    for (int d = 1; d < 6; d++) {
        char label[64];
        snprintf(label, sizeof label, "%s(\"abc\")", digests[d].name);
        hex(label, digests[d].fn("abc", 3, md), digests[d].size);
        snprintf(label, sizeof label, "%s(\"\")", digests[d].name);
        hex(label, digests[d].fn("", 0, md), digests[d].size);
        const char *msg = d < 4 ? two_block : two_block_512;
        snprintf(label, sizeof label, "%s(%zu-byte message)", digests[d].name, strlen(msg));
        hex(label, digests[d].fn(msg, (CC_LONG)strlen(msg), md), digests[d].size);
        snprintf(label, sizeof label, "%s(a million a)", digests[d].name);
        incremental(d, million, 1000000, 1000, md);
        hex(label, md, digests[d].size);
    }

    // every digest, every split of 300 bytes from 1 to 300 at a time
    unsigned char data[300];
    for (int i = 0; i < 300; i++)
        data[i] = (unsigned char)(i * 7 + 3);
    for (int d = 0; d < 6; d++) {
        unsigned char whole[64], parts[64];
        int same = 1;
        for (size_t len = 0; len <= 300; len += 37)
            for (size_t step = 1; step <= 300; step++) {
                digests[d].fn(data, (CC_LONG)len, whole);
                incremental(d, data, len, step, parts);
                same &= !memcmp(whole, parts, digests[d].size);
            }
        printf("%s: incremental and one-shot agree: %s\n", digests[d].name, same ? "yes" : "NO");
    }

    // HMAC: RFC 2202 (MD5, SHA-1) and RFC 4231 (SHA-2), test cases 1, 2 and 6
    unsigned char key20[20], key131[131];
    memset(key20, 0x0b, 20);
    memset(key131, 0xaa, 131);
    struct {
        const char *name;
        CCHmacAlgorithm alg;
        size_t size;
    } hmacs[] = {{"md5", kCCHmacAlgMD5, 16},       {"sha1", kCCHmacAlgSHA1, 20},
                 {"sha224", kCCHmacAlgSHA224, 28}, {"sha256", kCCHmacAlgSHA256, 32},
                 {"sha384", kCCHmacAlgSHA384, 48}, {"sha512", kCCHmacAlgSHA512, 64}};
    const char *big_key_text = "Test Using Larger Than Block-Size Key - Hash Key First";
    for (int h = 0; h < 6; h++) {
        char label[64];
        snprintf(label, sizeof label, "hmac-%s case 1", hmacs[h].name);
        CCHmac(hmacs[h].alg, key20, h == 0 ? 16 : 20, "Hi There", 8, md);
        hex(label, md, hmacs[h].size);
        snprintf(label, sizeof label, "hmac-%s case 2", hmacs[h].name);
        CCHmac(hmacs[h].alg, "Jefe", 4, "what do ya want for nothing?", 28, md);
        hex(label, md, hmacs[h].size);
        snprintf(label, sizeof label, "hmac-%s long key", hmacs[h].name);
        CCHmac(hmacs[h].alg, key131, h < 2 ? 80 : 131, big_key_text, strlen(big_key_text), md);
        hex(label, md, hmacs[h].size);
        // the incremental form, a byte at a time and in one go
        unsigned char inc[64];
        CCHmacContext ctx;
        CCHmacInit(&ctx, hmacs[h].alg, key131, h < 2 ? 80 : 131);
        for (size_t i = 0; i < strlen(big_key_text); i++)
            CCHmacUpdate(&ctx, big_key_text + i, 1);
        CCHmacFinal(&ctx, inc);
        printf("hmac-%s incremental agrees: %s\n", hmacs[h].name, memcmp(inc, md, hmacs[h].size) ? "NO" : "yes");
    }

    // PBKDF2: RFC 6070 (HMAC-SHA1) and RFC 7914 section 11 (HMAC-SHA256)
    struct {
        const char *password;
        size_t plen;
        const char *salt;
        size_t slen;
        unsigned rounds;
        size_t dlen;
        CCPseudoRandomAlgorithm prf;
    } kdf[] = {
        {"password", 8, "salt", 4, 1, 20, kCCPRFHmacAlgSHA1},
        {"password", 8, "salt", 4, 2, 20, kCCPRFHmacAlgSHA1},
        {"password", 8, "salt", 4, 4096, 20, kCCPRFHmacAlgSHA1},
        {"passwordPASSWORDpassword", 24, "saltSALTsaltSALTsaltSALTsaltSALTsalt", 36, 4096, 25, kCCPRFHmacAlgSHA1},
        {"pass\0word", 9, "sa\0lt", 5, 4096, 16, kCCPRFHmacAlgSHA1},
        {"passwd", 6, "salt", 4, 1, 64, kCCPRFHmacAlgSHA256},
        {"Password", 8, "NaCl", 4, 80000, 64, kCCPRFHmacAlgSHA256},
    };
    for (int i = 0; i < 7; i++) {
        unsigned char out[64];
        int rc = CCKeyDerivationPBKDF(kCCPBKDF2, kdf[i].password, kdf[i].plen, (const uint8_t *)kdf[i].salt,
                                      kdf[i].slen, kdf[i].prf, kdf[i].rounds, out, kdf[i].dlen);
        char label[64];
        snprintf(label, sizeof label, "pbkdf2-%s %u rounds (rc %d)", kdf[i].prf == kCCPRFHmacAlgSHA1 ? "sha1" : "sha256",
                 kdf[i].rounds, rc);
        hex(label, out, kdf[i].dlen);
    }
    unsigned char out[32];
    printf("pbkdf2 with no rounds: %d\n",
           CCKeyDerivationPBKDF(kCCPBKDF2, "x", 1, (const uint8_t *)"y", 1, kCCPRFHmacAlgSHA256, 0, out, 32));
    printf("pbkdf2 with an unknown PRF: %d\n",
           CCKeyDerivationPBKDF(kCCPBKDF2, "x", 1, (const uint8_t *)"y", 1, 9, 1, out, 32));
    unsigned rounds = CCCalibratePBKDF(kCCPBKDF2, 8, 16, kCCPRFHmacAlgSHA256, 32, 50);
    printf("calibrated rounds for 50 ms: %s\n", rounds > 0 && rounds != (unsigned)-1 ? "some" : "none");
    printf("calibrating an unknown algorithm: %d\n", (int)CCCalibratePBKDF(7, 8, 16, kCCPRFHmacAlgSHA256, 32, 50));

    // random bytes
    unsigned char r1[32], r2[32];
    int a = CCRandomGenerateBytes(r1, sizeof r1), b = CCRandomGenerateBytes(r2, sizeof r2);
    printf("random: %d %d, different: %s\n", a, b, memcmp(r1, r2, 32) ? "yes" : "no");
    printf("CCRandomCopyBytes: %d\n", CCRandomCopyBytes(kCCRandomDefault, r1, sizeof r1));

    // the published answers these must equal, spelled out once more and compared
    unsigned char want[64];
    size_t n;
    unhex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", want, &n);
    printf("sha256(\"abc\") is FIPS 180-4's: %s\n", memcmp(CC_SHA256("abc", 3, md), want, n) ? "NO" : "yes");
    free(million);
    return 0;
}
