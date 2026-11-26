/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 *   ferry [-v] PROGRAM [ARGUMENTS...]
 *   ferry [-v] APP.app [ARGUMENTS...]
 *   ferry [-v] INSTALLER.pkg | DISK-IMAGE.dmg
 *
 * Runs a program built for an Intel Mac, the program inside an app bundle,
 * or Ferry's own Installer for a Mac installer package or disk image.
 */
#include <ctype.h>
#include <dirent.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ferry.h"

#define FERRY_VERSION "0.80.0"

static void usage(FILE *out)
{
    fputs("Usage: ferry [-v] PROGRAM [ARGUMENTS...]\n"
          "       ferry [-v] APP.app [ARGUMENTS...]\n"
          "       ferry [-v] INSTALLER.pkg | DISK-IMAGE.dmg\n"
          "Runs a program built for an Intel Mac, or the app in a .app folder; opens a\n"
          "Mac installer package or disk image in Ferry's Installer.\n\n"
          "  -v, --verbose   say what Ferry loads and connects\n"
          "  -h, --help      show this help\n"
          "      --version   show Ferry's version\n"
          "      --list-symbols[=libSystem|libobjc|libFerryHost]\n"
          "                  list the calls Ferry provides (used to build its SDK)\n", out);
}

static int is_file(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}
static int is_dir(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

/* The program an app bundle runs: CFBundleExecutable in an XML Info.plist,
 * else the one named after the bundle, else the only file in Contents/MacOS. */
static int bundle_program(const char *app, char *out, size_t size)
{
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/Contents/Info.plist", app);
    FILE *f = fopen(path, "rb");
    if (f) {
        static char text[1 << 16];
        size_t n = fread(text, 1, sizeof text - 1, f);
        fclose(f);
        text[n] = 0;
        char *key = strstr(text, "<key>CFBundleExecutable</key>");
        char *open = key ? strstr(key, "<string>") : NULL;
        char *close = open ? strstr(open, "</string>") : NULL;
        if (close && close - open - 8 < 256) {
            snprintf(out, size, "%s/Contents/MacOS/%.*s", app, (int)(close - open - 8), open + 8);
            if (is_file(out))
                return 1;
        }
    }
    const char *base = strrchr(app, '/') ? strrchr(app, '/') + 1 : app;
    size_t len = strlen(base);
    if (len > 4 && !strcmp(base + len - 4, ".app")) {
        snprintf(out, size, "%s/Contents/MacOS/%.*s", app, (int)(len - 4), base);
        if (is_file(out))
            return 1;
    }
    snprintf(path, sizeof path, "%s/Contents/MacOS", app);
    DIR *d = opendir(path);
    int found = 0;
    for (struct dirent *e; d && (e = readdir(d));) {
        if (e->d_name[0] == '.')
            continue;
        snprintf(out, size, "%s/%s", path, e->d_name);
        if (is_file(out) && access(out, X_OK) == 0) {
            found = 1;
            break;
        }
    }
    if (d)
        closedir(d);
    return found;
}

static int has_suffix(const char *s, const char *suffix)
{
    size_t a = strlen(s), b = strlen(suffix);
    while (a > 0 && s[a - 1] == '/')
        a--;
    if (a < b)
        return 0;
    for (size_t i = 0; i < b; i++)
        if (tolower((unsigned char)s[a - b + i]) != suffix[i])
            return 0;
    return 1;
}

/* A flat installer package is a xar archive; a disk image ends in a "koly" trailer. */
static int is_installable(const char *path)
{
    if (has_suffix(path, ".pkg") || has_suffix(path, ".mpkg") || has_suffix(path, ".dmg"))
        return 1;
    FILE *f = fopen(path, "rb");
    if (!f)
        return 0;
    char magic[4] = {0};
    int xar = fread(magic, 1, 4, f) == 4 && !memcmp(magic, "xar!", 4);
    int koly = 0;
    if (!xar && fseek(f, -512, SEEK_END) == 0)
        koly = fread(magic, 1, 4, f) == 4 && !memcmp(magic, "koly", 4);
    fclose(f);
    return xar || koly;
}

/* Ferry's Installer, next to this program (installer/) or installed. */
static int find_installer(char *out, size_t size)
{
    const char *env = getenv("FERRY_INSTALLER");
    if (env && *env) {
        snprintf(out, size, "%s", env);
        return is_file(out);
    }
    char self[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", self, sizeof self - 64);
    if (n > 0) {
        self[n] = 0;
        char *slash = strrchr(self, '/');
        if (slash) {
            *slash = 0;
            snprintf(out, size, "%s/installer/Installer.app/Contents/MacOS/Installer", self);
            if (is_file(out))
                return 1;
        }
    }
    snprintf(out, size, "/usr/lib/ferry/Installer.app/Contents/MacOS/Installer");
    return is_file(out);
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
                                                   ferry_pthread_symbols, ferry_blocks_symbols,
                                                   ferry_dispatch_symbols, ferry_dispatch_io_symbols, ferry_commoncrypto_symbols,
                                                   ferry_sysversion_symbols, ferry_sysctl_symbols,
                                                   ferry_attrlist_symbols, ferry_dyld_symbols, ferry_wchar_symbols,
                                                   ferry_tlv_symbols, ferry_socket_symbols, ferry_kqueue_symbols,
                                                   ferry_libc_more_symbols, ferry_oslog_symbols,
                                                   ferry_swift_symbols, ferry_copyfile_symbols, ferry_libc_vlc_symbols,
                                                    ferry_libc_apps_symbols};
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
    /* Every Intel Mac had at least a Core 2 processor, and Mac programs are
     * built to use its instructions (SSSE3). Some older PCs, and virtual
     * machines set to a plain processor, lack them; such a program stops
     * with "Illegal instruction" the first time it uses one, so say why
     * before it does. */
    __builtin_cpu_init();
    if (!__builtin_cpu_supports("ssse3"))
        fprintf(stderr, "ferry: this processor lacks SSSE3, which every Intel Mac had; a Mac program may stop "
                        "with \"Illegal instruction\" (in a virtual machine, give it the host's processor)\n");
    static char program[PATH_MAX];
    if (is_dir(argv[i]) && !has_suffix(argv[i], ".pkg") && !has_suffix(argv[i], ".mpkg")) {
        if (!bundle_program(argv[i], program, sizeof program)) {
            fprintf(stderr, "ferry: %s isn't an app: it has no program in Contents/MacOS\n", argv[i]);
            return 126;
        }
        argv[i] = program;
    } else if (is_installable(argv[i])) {
        if (!find_installer(program, sizeof program)) {
            fprintf(stderr, "ferry: %s is a Mac installer or disk image, but Ferry's Installer isn't here\n", argv[i]);
            return 126;
        }
        /* the package, then any of the Installer's own options */
        char *file = argv[i];
        char **args = calloc((size_t)(argc - i + 2), sizeof *args);
        args[0] = program;
        args[1] = file;
        for (int k = i + 1; k < argc; k++)
            args[k - i + 1] = argv[k];
        exit(ferry_run(program, argc - i + 1, args, envp));
    }
    /* The program sees itself as argv[0], as it would on a Mac. */
    ferry_commpage_init();
    ferry_thread_tsd_init();
    exit(ferry_run(argv[i], argc - i, argv + i, envp));
}
