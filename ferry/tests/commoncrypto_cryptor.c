// SPDX-License-Identifier: GPL-3.0-or-later
// CommonCrypto's encryption against published test vectors: AES-128, -192
// and -256 from FIPS 197 appendix C (ECB, one block), and CBC and CTR from
// NIST SP 800-38A appendix F; then PKCS #7 padding, the status codes the
// manual pages document, and CCCryptor's incremental form fed in uneven
// pieces, which must give what CCCrypt gives in one go.
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

static size_t unhex(const char *s, unsigned char *out)
{
    size_t n = 0;
    for (; s[0] && s[1]; s += 2) {
        unsigned v;
        sscanf(s, "%2x", &v);
        out[n++] = (unsigned char)v;
    }
    return n;
}

static void check(const char *what, const unsigned char *got, size_t n, const char *want_hex)
{
    unsigned char want[256];
    size_t wn = unhex(want_hex, want);
    printf("%s: %s\n", what, wn == n && !memcmp(got, want, n) ? "matches" : "DIFFERS");
    if (wn != n || memcmp(got, want, n))
        hex("  got", got, n);
}

// SP 800-38A's four-block plaintext
static const char *PT = "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51"
                        "30c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710";

int main(void)
{
    unsigned char key[32], iv[16], in[256], out[512], back[512];
    size_t moved, n;
    CCCryptorStatus rc;

    // FIPS 197, appendix C.1 to C.3
    const char *keys[3] = {"000102030405060708090a0b0c0d0e0f", "000102030405060708090a0b0c0d0e0f1011121314151617",
                           "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"};
    const char *cts[3] = {"69c4e0d86a7b0430d8cdb78070b4c55a", "dda97ca4864cdfe06eaf70a0ec0d7191",
                          "8ea2b7ca516745bfeafc49904b496089"};
    for (int i = 0; i < 3; i++) {
        size_t kl = unhex(keys[i], key);
        n = unhex("00112233445566778899aabbccddeeff", in);
        rc = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionECBMode, key, kl, NULL, in, n, out, sizeof out, &moved);
        char what[64];
        snprintf(what, sizeof what, "AES-%zu ECB encrypt (rc %d, %zu bytes)", kl * 8, rc, moved);
        check(what, out, moved, cts[i]);
        rc = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionECBMode, key, kl, NULL, out, moved, back, sizeof back,
                     &moved);
        snprintf(what, sizeof what, "AES-%zu ECB decrypt (rc %d, %zu bytes)", kl * 8, rc, moved);
        check(what, back, moved, "00112233445566778899aabbccddeeff");
    }

    // SP 800-38A F.2.1 (CBC-AES128) and F.2.5 (CBC-AES256)
    n = unhex(PT, in);
    unhex("000102030405060708090a0b0c0d0e0f", iv);
    size_t kl = unhex("2b7e151628aed2a6abf7158809cf4f3c", key);
    rc = CCCrypt(kCCEncrypt, kCCAlgorithmAES, 0, key, kl, iv, in, n, out, sizeof out, &moved);
    printf("CBC-AES128: rc %d, %zu bytes\n", rc, moved);
    check("CBC-AES128 encrypt", out, moved,
          "7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2"
          "73bed6b8e3c1743b7116e69e222295163ff1caa1681fac09120eca307586e1a7");
    rc = CCCrypt(kCCDecrypt, kCCAlgorithmAES, 0, key, kl, iv, out, moved, back, sizeof back, &moved);
    check("CBC-AES128 decrypt", back, moved, PT);
    kl = unhex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4", key);
    rc = CCCrypt(kCCEncrypt, kCCAlgorithmAES, 0, key, kl, iv, in, n, out, sizeof out, &moved);
    check("CBC-AES256 encrypt", out, moved,
          "f58c4c04d6e5f1ba779eabfb5f7bfbd69cfc4e967edb808d679f777bc6702c7d"
          "39f23369a9d9bacfa530e26304231461b2eb05e2c39be9fcda6c19078c6a9d1b");
    // decrypted in place
    memcpy(back, out, moved);
    rc = CCCrypt(kCCDecrypt, kCCAlgorithmAES, 0, key, kl, iv, back, moved, back, sizeof back, &moved);
    printf("CBC-AES256 in place: rc %d\n", rc);
    check("CBC-AES256 decrypt in place", back, moved, PT);

    // SP 800-38A F.5.1 (CTR-AES128), through CCCryptorCreateWithMode
    kl = unhex("2b7e151628aed2a6abf7158809cf4f3c", key);
    unhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", iv);
    CCCryptorRef c;
    rc = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCTR, kCCAlgorithmAES, ccNoPadding, iv, key, kl, NULL, 0, 0,
                                 kCCModeOptionCTR_BE, &c);
    printf("CTR create: rc %d\n", rc);
    size_t total = 0;
    // a stream: what goes in comes straight out, in any piece size
    size_t pieces[] = {5, 11, 16, 1, 31};
    for (int i = 0; i < 5; i++) {
        rc = CCCryptorUpdate(c, in + total, pieces[i], out + total, sizeof out - total, &moved);
        printf("  CTR update %zu: rc %d, moved %zu\n", pieces[i], rc, moved);
        total += moved;
    }
    rc = CCCryptorFinal(c, out + total, sizeof out - total, &moved);
    printf("  CTR final: rc %d, moved %zu\n", rc, moved);
    check("CTR-AES128 encrypt", out, total,
          "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff"
          "5ae4df3edbd5d35e5b4f09020db03eab1e031dda2fbe03d1792170a0f3009cee");
    CCCryptorRelease(c);
    rc = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES, ccNoPadding, iv, key, kl, NULL, 0, 0, 0,
                                 &c);
    CCCryptorUpdate(c, out, total, back, sizeof back, &moved);
    check("CTR-AES128 decrypt", back, moved, PT);
    CCCryptorRelease(c);

    // PKCS #7 padding: a whole block of padding after a whole block, none
    // missing for short messages; checked against itself and by length
    kl = unhex("2b7e151628aed2a6abf7158809cf4f3c", key);
    unhex("000102030405060708090a0b0c0d0e0f", iv);
    size_t lengths[] = {0, 1, 5, 15, 16, 17, 64};
    for (int i = 0; i < 7; i++) {
        for (size_t j = 0; j < lengths[i]; j++)
            in[j] = (unsigned char)('a' + j % 26);
        rc = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, kl, iv, in, lengths[i], out,
                     sizeof out, &moved);
        size_t clen = moved;
        rc = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, kl, iv, out, clen, back, sizeof back,
                     &moved);
        printf("padded %2zu bytes -> %2zu bytes, back to %2zu (rc %d), same: %s\n", lengths[i], clen, moved, rc,
               moved == lengths[i] && !memcmp(in, back, moved) ? "yes" : "NO");
        if (lengths[i] == 5)
            hex("  \"abcde\" encrypted", out, clen);
    }
    // the last block's padding, spoilt: a decode error
    memcpy(in, "abcde", 5);
    CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, kl, iv, in, 5, out, sizeof out, &moved);
    out[15] ^= 0x01;
    rc = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, kl, iv, out, 16, back, sizeof back,
                 &moved);
    printf("spoilt padding: rc %d, moved %zu\n", rc, moved);

    // the documented status codes
    rc = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, kl, iv, in, 20, out, 16, &moved);
    printf("buffer too small: rc %d, needs %zu\n", rc, moved);
    rc = CCCrypt(kCCEncrypt, kCCAlgorithmAES, 0, key, kl, iv, in, 20, out, sizeof out, &moved);
    printf("20 bytes without padding: rc %d\n", rc);
    rc = CCCrypt(kCCEncrypt, kCCAlgorithmAES, 0, key, 15, iv, in, 16, out, sizeof out, &moved);
    printf("a 15-byte key: rc %d\n", rc);
    rc = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCTR, kCCAlgorithmAES, ccNoPadding, iv, key, kl, NULL, 0, 0,
                                 kCCModeOptionCTR_LE, &c);
    printf("a little-endian counter: rc %d\n", rc);
    rc = CCCrypt(kCCEncrypt, kCCAlgorithm3DES, 0, key, kCCKeySize3DES, iv, in, 16, out, sizeof out, &moved);
    printf("3DES: rc %d\n", rc);
    rc = CCCryptorCreate(kCCEncrypt, kCCAlgorithmAES, 0x80, key, kl, iv, &c);
    printf("an unknown option: rc %d\n", rc);

    // CCCryptor in uneven pieces, CBC with padding, both ways: each update
    // moves only whole blocks, and decrypting holds the last block back for
    // the final step
    for (int i = 0; i < 100; i++)
        in[i] = (unsigned char)(i * 13 + 1);
    unsigned char whole[256];
    size_t whole_len;
    CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, kl, iv, in, 100, whole, sizeof whole, &whole_len);
    size_t steps[] = {7, 9, 16, 3, 33, 32};
    for (int dir = 0; dir < 2; dir++) {
        const unsigned char *src = dir ? whole : in;
        size_t len = dir ? whole_len : 100;
        rc = CCCryptorCreate(dir ? kCCDecrypt : kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, kl, iv, &c);
        printf("%s in pieces:\n", dir ? "decrypting" : "encrypting");
        size_t pos = 0, got = 0;
        for (int i = 0; pos < len; i++) {
            size_t step = steps[i % 6] < len - pos ? steps[i % 6] : len - pos;
            size_t expect = CCCryptorGetOutputLength(c, step, false);
            rc = CCCryptorUpdate(c, src + pos, step, out + got, sizeof out - got, &moved);
            printf("  update %2zu: rc %d, moved %2zu (output length said %zu)\n", step, rc, moved, expect);
            pos += step, got += moved;
        }
        printf("  final length said %zu\n", CCCryptorGetOutputLength(c, 0, true));
        rc = CCCryptorFinal(c, out + got, sizeof out - got, &moved);
        printf("  final: rc %d, moved %zu\n", rc, moved);
        got += moved;
        if (dir)
            printf("  same as the original: %s\n", got == 100 && !memcmp(out, in, 100) ? "yes" : "NO");
        else
            printf("  same as CCCrypt's: %s\n", got == whole_len && !memcmp(out, whole, got) ? "yes" : "NO");
        // reset with the same IV and do it again in one piece
        rc = CCCryptorReset(c, iv);
        size_t again = 0;
        CCCryptorUpdate(c, src, len, back, sizeof back, &moved);
        again = moved;
        CCCryptorFinal(c, back + again, sizeof back - again, &moved);
        again += moved;
        printf("  after a reset (rc %d): %s\n", rc, again == got && !memcmp(back, out, got) ? "the same again" : "DIFFERENT");
        CCCryptorRelease(c);
    }
    // a final step into too small a space
    CCCryptorCreate(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, kl, iv, &c);
    CCCryptorUpdate(c, in, 5, out, sizeof out, &moved);
    rc = CCCryptorFinal(c, out, 8, &moved);
    printf("final into 8 bytes: rc %d, needs %zu\n", rc, moved);
    CCCryptorRelease(c);
    return 0;
}
