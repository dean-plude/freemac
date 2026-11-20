/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 *   ferry [-v] PROGRAM [ARGUMENTS...]
 *
 * Runs a command-line program built for an Intel Mac.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ferry.h"

#define FERRY_VERSION "0.4.0"

static void usage(FILE *out)
{
    fputs("Usage: ferry [-v] PROGRAM [ARGUMENTS...]\n"
          "Runs a command-line program built for an Intel Mac.\n\n"
          "  -v, --verbose   say what Ferry loads and connects\n"
          "  -h, --help      show this help\n"
          "      --version   show Ferry's version\n"
          "      --list-symbols[=libSystem|libobjc|libFerryHost]\n"
          "                  list the calls Ferry provides (used to build its SDK)\n", out);
}

int main(int argc, char **argv, char **envp)
{
    int i = 1;
    for (; i < argc && argv[i][0] == '-'; i++) {
        if (!strcmp(argv[i], "-v") || !strcmp(argv[i], "--verbose")) {
            ferry_verbose = 1;
        } else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            usage(stdout);
            return 0;
        } else if (!strcmp(argv[i], "--list-symbols") || !strcmp(argv[i], "--list-symbols=libSystem")) {
            /* Everything Ferry provides, spelled as in Mach-O; the SDK's
             * description of libSystem is generated from this. */
            const struct ferry_symbol *tables[] = {ferry_core_symbols, ferry_stdio_symbols, ferry_posix_symbols,
                                                   ferry_blocks_symbols};
            for (size_t t = 0; t < sizeof tables / sizeof tables[0]; t++)
                for (const struct ferry_symbol *s = tables[t]; s->name; s++)
                    printf("_%s\n", s->name);
            for (const char *const *p = ferry_passthrough; *p; p++)
                printf("_%s\n", *p);
            return 0;
        } else if (!strcmp(argv[i], "--list-symbols=libobjc")) {
            for (const struct ferry_symbol *s = ferry_objc_symbols; s->name; s++)
                printf("_%s\n", s->name);
            return 0;
        } else if (!strcmp(argv[i], "--list-symbols=libFerryHost")) {
            for (const char *const *p = ferry_host_names; *p; p++)
                printf("_%s\n", *p);
            return 0;
        } else if (!strcmp(argv[i], "--version")) {
            puts("ferry " FERRY_VERSION);
            return 0;
        } else if (!strcmp(argv[i], "--")) {
            i++;
            break;
        } else {
            usage(stderr);
            return 2;
        }
    }
    if (i >= argc) {
        usage(stderr);
        return 2;
    }
    if (getenv("FERRY_VERBOSE"))
        ferry_verbose = 1;
    /* The program sees itself as argv[0], as it would on a Mac. */
    exit(ferry_run(argv[i], argc - i, argv + i, envp));
}
