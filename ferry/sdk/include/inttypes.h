/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The printf and scanf formats for the sized integer types, and the
 * intmax_t calls (freemac 1.221, Ferry 0.45.0). The formats are the
 * compiler's own for the Mac target (int64_t is a long long there). */
#ifndef _FERRY_INTTYPES_H_
#define _FERRY_INTTYPES_H_
#include <_ferry.h>
#include <stdint.h>
__FERRY_BEGIN

#define PRId8 __INT8_FMTd__
#define PRIi8 __INT8_FMTi__
#define PRIo8 __UINT8_FMTo__
#define PRIu8 __UINT8_FMTu__
#define PRIx8 __UINT8_FMTx__
#define PRIX8 __UINT8_FMTX__
#define PRId16 __INT16_FMTd__
#define PRIi16 __INT16_FMTi__
#define PRIo16 __UINT16_FMTo__
#define PRIu16 __UINT16_FMTu__
#define PRIx16 __UINT16_FMTx__
#define PRIX16 __UINT16_FMTX__
#define PRId32 __INT32_FMTd__
#define PRIi32 __INT32_FMTi__
#define PRIo32 __UINT32_FMTo__
#define PRIu32 __UINT32_FMTu__
#define PRIx32 __UINT32_FMTx__
#define PRIX32 __UINT32_FMTX__
#define PRId64 __INT64_FMTd__
#define PRIi64 __INT64_FMTi__
#define PRIo64 __UINT64_FMTo__
#define PRIu64 __UINT64_FMTu__
#define PRIx64 __UINT64_FMTx__
#define PRIX64 __UINT64_FMTX__
#define PRIdMAX __INTMAX_FMTd__
#define PRIiMAX __INTMAX_FMTi__
#define PRIoMAX __UINTMAX_FMTo__
#define PRIuMAX __UINTMAX_FMTu__
#define PRIxMAX __UINTMAX_FMTx__
#define PRIXMAX __UINTMAX_FMTX__
#define PRIdPTR __INTPTR_FMTd__
#define PRIiPTR __INTPTR_FMTi__
#define PRIoPTR __UINTPTR_FMTo__
#define PRIuPTR __UINTPTR_FMTu__
#define PRIxPTR __UINTPTR_FMTx__
#define PRIXPTR __UINTPTR_FMTX__
#define PRIdLEAST64 PRId64
#define PRIuLEAST64 PRIu64
#define PRIdFAST64 PRId64
#define PRIuFAST64 PRIu64

#define SCNd8 "hhd"
#define SCNu8 "hhu"
#define SCNx8 "hhx"
#define SCNd16 "hd"
#define SCNu16 "hu"
#define SCNx16 "hx"
#define SCNd32 "d"
#define SCNu32 "u"
#define SCNx32 "x"
#define SCNd64 "lld"
#define SCNu64 "llu"
#define SCNx64 "llx"
#define SCNdMAX "jd"
#define SCNuMAX "ju"
#define SCNdPTR "ld"
#define SCNuPTR "lu"
/* the rest of C99's scanf macros, as on a Mac */
#define SCNdLEAST8 "hhd"
#define SCNdFAST8 "hhd"
#define SCNdLEAST16 "hd"
#define SCNdFAST16 "hd"
#define SCNdLEAST32 "d"
#define SCNdFAST32 "d"
#define SCNdLEAST64 "lld"
#define SCNdFAST64 "lld"
#define SCNi8 "hhi"
#define SCNiLEAST8 "hhi"
#define SCNiFAST8 "hhi"
#define SCNi16 "hi"
#define SCNiLEAST16 "hi"
#define SCNiFAST16 "hi"
#define SCNi32 "i"
#define SCNiLEAST32 "i"
#define SCNiFAST32 "i"
#define SCNi64 "lli"
#define SCNiLEAST64 "lli"
#define SCNiFAST64 "lli"
#define SCNiMAX "ji"
#define SCNiPTR "li"
#define SCNo8 "hho"
#define SCNoLEAST8 "hho"
#define SCNoFAST8 "hho"
#define SCNo16 "ho"
#define SCNoLEAST16 "ho"
#define SCNoFAST16 "ho"
#define SCNo32 "o"
#define SCNoLEAST32 "o"
#define SCNoFAST32 "o"
#define SCNo64 "llo"
#define SCNoLEAST64 "llo"
#define SCNoFAST64 "llo"
#define SCNoMAX "jo"
#define SCNoPTR "lo"
#define SCNuLEAST8 "hhu"
#define SCNuFAST8 "hhu"
#define SCNuLEAST16 "hu"
#define SCNuFAST16 "hu"
#define SCNuLEAST32 "u"
#define SCNuFAST32 "u"
#define SCNuLEAST64 "llu"
#define SCNuFAST64 "llu"
#define SCNxLEAST8 "hhx"
#define SCNxFAST8 "hhx"
#define SCNxLEAST16 "hx"
#define SCNxFAST16 "hx"
#define SCNxLEAST32 "x"
#define SCNxFAST32 "x"
#define SCNxLEAST64 "llx"
#define SCNxFAST64 "llx"
#define SCNxMAX "jx"
#define SCNxPTR "lx"

typedef struct { intmax_t quot, rem; } imaxdiv_t;
intmax_t imaxabs(intmax_t j);
imaxdiv_t imaxdiv(intmax_t numer, intmax_t denom);
intmax_t strtoimax(const char *nptr, char **endptr, int base);
uintmax_t strtoumax(const char *nptr, char **endptr, int base);

__FERRY_END
#endif
