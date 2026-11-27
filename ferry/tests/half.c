/* SPDX-License-Identifier: GPL-3.0-or-later
 * Half-precision floats: the Mac's compiler turns them to and from float
 * by calling __extendhfsf2 and __truncsfhf2 with the half as a 16-bit
 * integer (in %edi and %ax), as Metal shaders that pack values into halves
 * do (Godot's fog). */
#include <stdio.h>
#include <string.h>

static void show(float f)
{
    volatile _Float16 h = (_Float16)f;
    unsigned short bits;
    memcpy(&bits, (const void *)&h, 2);
    printf("%g -> %04x -> %g\n", f, bits, (double)(float)h);
}

int main(void)
{
    float v[] = {0.0f, 1.0f, -2.5f, 0.333f, 65504.0f, 1e-5f, 100000.0f};
    for (unsigned i = 0; i < sizeof v / sizeof v[0]; i++)
        show(v[i]);
    volatile double d = 0.1;
    volatile _Float16 hd = (_Float16)d;
    printf("double 0.1 -> %g\n", (double)(float)hd);
    return 0;
}
