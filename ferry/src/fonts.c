/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A Mac's font folders (freemac 1.248, Ferry 0.71.0).
 *
 * A Mac keeps fonts flat in a Fonts folder of each Library: ~/Library/Fonts
 * for the user's own, /Library/Fonts for the computer's and
 * /System/Library/Fonts for the system's. Programs list such a folder and
 * open each file in it with FreeType (OBS Studio's Text source does, with
 * the Library folders NSSearchPathForDirectoriesInDomains gives), or open a
 * font by its Mac path. This system keeps fonts in a fonts folder of each
 * data folder instead (~/.local/share/fonts, /usr/local/share/fonts,
 * /usr/share/fonts), in folders of their own.
 *
 * So each of those Fonts folders, the Mac's and the one in the Library
 * folder Ferry gives for each domain (~/.local/share/Fonts and so on), when
 * no real one is there, is a folder of links Ferry keeps in the user's
 * cache: one link for each font file in that domain's fonts folder and the
 * folders in it, named as the file is. It is made again when the fonts
 * change, so a font put in later is in it. A path into one of those folders
 * is taken to the same name in the links folder before it reaches the
 * system: opening, stat, access and listing it all agree.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ferry.h"

enum { USER, LOCAL, SYSTEM, NDOMAINS };
static const char *const domain_name[NDOMAINS] = {"user", "local", "system"};

struct entry { char *name, *path; };
struct list { struct entry *e; size_t n, cap; };

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static char folder[NDOMAINS][PATH_MAX]; /* the links folder made in this run, "" if not yet */

static const char *home(void)
{
    const char *h = getenv("HOME");
    return h && *h ? h : "/";
}

/* The data folder Ferry gives as a domain's Library (NSObject.m). */
static void library(int domain, char *out, size_t n)
{
    const char *x;
    if (domain == USER) {
        if ((x = getenv("XDG_DATA_HOME")) && x[0] == '/')
            snprintf(out, n, "%s", x);
        else
            snprintf(out, n, "%s/.local/share", home());
    } else
        snprintf(out, n, "%s", domain == LOCAL ? "/usr/local/share" : "/usr/share");
}

static int is_font(const char *name)
{
    static const char *const ext[] = {".ttf", ".otf", ".ttc", ".otc", ".pfb", ".pfa", ".dfont", ".woff", ".woff2"};
    const char *dot = strrchr(name, '.');
    if (!dot || name[0] == '.')
        return 0;
    for (size_t i = 0; i < sizeof ext / sizeof *ext; i++)
        if (!strcasecmp(dot, ext[i]))
            return 1;
    return 0;
}

static int by_name(const void *a, const void *b)
{
    return strcmp(((const struct entry *)a)->name, ((const struct entry *)b)->name);
}

/* Every font file under dir, deepest folders included, to a bounded depth. */
static void collect(const char *dir, int depth, struct list *l)
{
    DIR *d = depth < 8 ? opendir(dir) : NULL;
    if (!d)
        return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.')
            continue;
        char p[PATH_MAX];
        if (snprintf(p, sizeof p, "%s/%s", dir, e->d_name) >= (int)sizeof p)
            continue;
        struct stat s;
        if (stat(p, &s) != 0)
            continue;
        if (S_ISDIR(s.st_mode))
            collect(p, depth + 1, l);
        else if (S_ISREG(s.st_mode) && is_font(e->d_name)) {
            if (l->n == l->cap) {
                size_t cap = l->cap ? l->cap * 2 : 64;
                struct entry *bigger = realloc(l->e, cap * sizeof *bigger);
                if (!bigger)
                    break;
                l->e = bigger, l->cap = cap;
            }
            l->e[l->n].name = strdup(e->d_name);
            l->e[l->n].path = strdup(p);
            if (l->e[l->n].name && l->e[l->n].path)
                l->n++;
        }
    }
    closedir(d);
}

static void free_list(struct list *l)
{
    for (size_t i = 0; i < l->n; i++)
        free(l->e[i].name), free(l->e[i].path);
    free(l->e);
}

static uint64_t hash(uint64_t h, const char *s)
{
    for (; *s; s++)
        h = (h ^ (unsigned char)*s) * 1099511628211ull;
    return (h ^ 0xff) * 1099511628211ull;
}

static int mkdirs(char *p)
{
    for (char *s = p + 1; *s; s++)
        if (*s == '/') {
            *s = 0;
            int rc = mkdir(p, 0700);
            *s = '/';
            if (rc != 0 && errno != EEXIST)
                return -1;
        }
    return mkdir(p, 0700) == 0 || errno == EEXIST ? 0 : -1;
}

static void remove_folder(const char *p)
{
    DIR *d = opendir(p);
    if (d) {
        struct dirent *e;
        while ((e = readdir(d)))
            if (strcmp(e->d_name, ".") && strcmp(e->d_name, "..")) {
                char q[PATH_MAX];
                if (snprintf(q, sizeof q, "%s/%s", p, e->d_name) < (int)sizeof q)
                    unlink(q);
            }
        closedir(d);
    }
    rmdir(p);
}

/* The links folder for a domain, made if the fonts changed since it was.
 * Called with the lock held. */
static const char *links_folder(int domain)
{
    if (folder[domain][0])
        return folder[domain];
    char lib[PATH_MAX], src[PATH_MAX];
    struct list l = {0};
    library(domain, lib, sizeof lib);
    snprintf(src, sizeof src, "%s/fonts", lib);
    collect(src, 0, &l);
    if (domain == USER) { /* the older place for a user's own fonts */
        snprintf(src, sizeof src, "%s/.fonts", home());
        collect(src, 0, &l);
    }
    if (l.n > 1)
        qsort(l.e, l.n, sizeof *l.e, by_name);
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < l.n; i++)
        h = hash(hash(h, l.e[i].name), l.e[i].path);

    const char *x = getenv("XDG_CACHE_HOME");
    char base[PATH_MAX], dir[PATH_MAX], tmp[PATH_MAX];
    if (x && x[0] == '/')
        snprintf(base, sizeof base, "%s/freemac/ferry/Fonts", x);
    else
        snprintf(base, sizeof base, "%s/.cache/freemac/ferry/Fonts", home());
    snprintf(dir, sizeof dir, "%s/%s-%016llx", base, domain_name[domain], (unsigned long long)h);
    struct stat s;
    if (stat(dir, &s) != 0 || !S_ISDIR(s.st_mode)) {
        /* made aside and moved in whole, so another program never sees half */
        snprintf(tmp, sizeof tmp, "%s.%d", dir, (int)getpid());
        remove_folder(tmp);
        if (mkdirs(tmp) == 0) {
            for (size_t i = 0; i < l.n; i++) {
                if (i && !strcmp(l.e[i].name, l.e[i - 1].name))
                    continue; /* the first of two files with one name */
                char link[PATH_MAX];
                if (snprintf(link, sizeof link, "%s/%s", tmp, l.e[i].name) < (int)sizeof link &&
                    symlink(l.e[i].path, link) != 0)
                    continue; /* a font left out, the rest still there */
            }
            if (rename(tmp, dir) != 0) /* another program made it first */
                remove_folder(tmp);
            /* the folders made for fonts there were before */
            size_t plen = strlen(domain_name[domain]);
            DIR *d = opendir(base);
            struct dirent *e;
            while (d && (e = readdir(d))) {
                char old[PATH_MAX];
                if (strncmp(e->d_name, domain_name[domain], plen) || e->d_name[plen] != '-' ||
                    strchr(e->d_name, '.') || snprintf(old, sizeof old, "%s/%s", base, e->d_name) >= (int)sizeof old ||
                    !strcmp(old, dir))
                    continue;
                remove_folder(old);
            }
            if (d)
                closedir(d);
        }
    }
    free_list(&l);
    if (stat(dir, &s) != 0 || !S_ISDIR(s.st_mode))
        return NULL;
    snprintf(folder[domain], sizeof folder[domain], "%s", dir);
    return folder[domain];
}

/* The rest of path after prefix/Fonts ("" or "/name"), or NULL. */
static const char *after_fonts(const char *path, const char *prefix)
{
    size_t n = strlen(prefix);
    if (strncmp(path, prefix, n) || strncmp(path + n, "/Fonts", 6))
        return NULL;
    const char *rest = path + n + 6;
    return *rest == 0 || *rest == '/' ? rest : NULL;
}

/* A path with repeated slashes taken as one and a trailing one dropped. */
static void tidy(const char *in, char *out, size_t n)
{
    size_t j = 0;
    for (size_t i = 0; in[i] && j + 1 < n; i++)
        if (!(in[i] == '/' && j && out[j - 1] == '/'))
            out[j++] = in[i];
    while (j > 1 && out[j - 1] == '/')
        j--;
    out[j] = 0;
}

const char *ferry_font_path(const char *path, char *buf, size_t size)
{
    if (!path || path[0] != '/' || !strstr(path, "/Fonts"))
        return path;
    char p[PATH_MAX], lib[PATH_MAX], mac[PATH_MAX];
    tidy(path, p, sizeof p);
    int domain = -1;
    const char *rest = NULL;
    /* the Mac's own folders */
    if ((rest = after_fonts(p, "/System/Library")))
        domain = SYSTEM;
    else if ((rest = after_fonts(p, "/Library")))
        domain = LOCAL;
    else {
        snprintf(mac, sizeof mac, "%s/Library", home());
        if ((rest = after_fonts(p, mac)))
            domain = USER;
    }
    /* the Library folders Ferry gives */
    for (int d = 0; domain < 0 && d < NDOMAINS; d++) {
        library(d, lib, sizeof lib);
        if ((rest = after_fonts(p, lib)))
            domain = d;
    }
    if (domain < 0 || strstr(rest, "/.."))
        return path;
    /* a real Fonts folder there is left as it is */
    char real[PATH_MAX];
    struct stat s;
    snprintf(real, sizeof real, "%.*s", (int)(rest - p), p);
    if (lstat(real, &s) == 0)
        return path;
    pthread_mutex_lock(&lock);
    const char *dir = links_folder(domain);
    char out[PATH_MAX];
    int ok = dir && snprintf(out, sizeof out, "%s%s", dir, rest) < (int)sizeof out;
    pthread_mutex_unlock(&lock);
    if (!ok || strlen(out) >= size)
        return path;
    memcpy(buf, out, strlen(out) + 1);
    return buf;
}
