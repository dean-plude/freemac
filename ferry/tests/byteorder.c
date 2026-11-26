/* SPDX-License-Identifier: GPL-3.0-or-later */
/* libkern/OSByteOrder.h, as a Mac's CoreFoundation brings it in
 * (VLC's Core Text fonts swap with it). */
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

int main(void)
{
    unsigned char b[8] = { 1, 2, 3, 4, 5, 6, 7, 8 };
    printf("host order is little: %d\n", OSHostByteOrder() == OSLittleEndian);
    printf("to little: %x, to big: %x\n", OSSwapHostToLittleInt32(0x11223344),
           OSSwapHostToBigInt32(0x11223344));
    printf("read big: %x, read little: %x\n", OSReadBigInt32(b, 0),
           OSReadLittleInt16(b, 6));
    OSWriteBigInt16(b, 0, 0xabcd);
    printf("written big: %02x %02x\n", b[0], b[1]);
    printf("64: %llx\n", (unsigned long long)OSSwapInt64(0x0102030405060708ULL));
    return 0;
}
