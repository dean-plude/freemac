/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The macOS version Ferry presents, and the Mac's version file.
 *
 * Programs (and updaters such as Sparkle) ask which macOS they run on in
 * several ways: uname's Darwin release (posix.c), NSProcessInfo's
 * operatingSystemVersion and Gestalt (Foundation), and by reading
 * /System/Library/CoreServices/SystemVersion.plist, the property list a Mac
 * keeps there. All of them answer from the numbers in ferry.h, so they
 * agree. The version file doesn't exist on this system: reading it, and
 * asking about it with stat or access, gets a read-only file Ferry makes
 * in memory. Its keys are the ones Apple documents for the file.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ferry.h"

static const char version_file[] = "/System/Library/CoreServices/SystemVersion.plist";

static const char version_plist[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    "<plist version=\"1.0\">\n"
    "<dict>\n"
    "\t<key>ProductBuildVersion</key>\n"
    "\t<string>" FERRY_MACOS_BUILD "</string>\n"
    "\t<key>ProductName</key>\n"
    "\t<string>macOS</string>\n"
    "\t<key>ProductUserVisibleVersion</key>\n"
    "\t<string>" FERRY_MACOS_VERSION "</string>\n"
    "\t<key>ProductVersion</key>\n"
    "\t<string>" FERRY_MACOS_VERSION "</string>\n"
    "</dict>\n"
    "</plist>\n";

/* For Ferry's Foundation (NSProcessInfo and Gestalt). */
const char *ferry_macos_version(const char **build)
{
    if (build)
        *build = FERRY_MACOS_BUILD;
    return FERRY_MACOS_VERSION;
}

/* The path with repeated slashes taken as one, as the system does. */
static int is_version_file(const char *path)
{
    if (!path || path[0] != '/')
        return 0;
    const char *a = path, *b = version_file;
    while (*a && *b) {
        if (*a != *b)
            return 0;
        if (*a == '/')
            while (a[1] == '/')
                a++;
        a++, b++;
    }
    return !*a && !*b;
}

int ferry_is_virtual(const char *path) { return is_version_file(path); }

/* A descriptor reading the file from its start, or -1 with errno set. */
int ferry_virtual_open(const char *path, int linux_flags)
{
    if (!is_version_file(path)) {
        errno = ENOENT;
        return -1;
    }
    if ((linux_flags & O_ACCMODE) != O_RDONLY || (linux_flags & (O_CREAT | O_TRUNC))) {
        errno = EACCES; /* it belongs to the system */
        return -1;
    }
    int fd = memfd_create("SystemVersion.plist", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0)
        return -1;
    size_t len = sizeof version_plist - 1;
    if (write(fd, version_plist, len) != (ssize_t)len || lseek(fd, 0, SEEK_SET) != 0) {
        int e = errno;
        close(fd);
        errno = e ? e : EIO;
        return -1;
    }
    fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE | F_SEAL_SEAL);
    if (!(linux_flags & O_CLOEXEC))
        fcntl(fd, F_SETFD, 0);
    return fd;
}

/* What stat says about it: a plain file the system owns, readable by all. */
int ferry_virtual_stat(const char *path, struct stat *s)
{
    if (!is_version_file(path))
        return 0;
    memset(s, 0, sizeof *s);
    s->st_mode = S_IFREG | 0644;
    s->st_nlink = 1;
    s->st_size = sizeof version_plist - 1;
    s->st_blksize = 4096;
    s->st_blocks = 8;
    /* a fixed time, so that the file looks the same on every run */
    s->st_mtim.tv_sec = s->st_ctim.tv_sec = s->st_atim.tv_sec = 1704067200; /* 2024-01-01 */
    return 1;
}
