/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _STRING_H_
#define _STRING_H_
#include <_ferry.h>
__FERRY_BEGIN
void *memcpy(void *, const void *, size_t);
void *memmove(void *, const void *, size_t);
void *memset(void *, int, size_t);
int memcmp(const void *, const void *, size_t);
void *memchr(const void *, int, size_t);
void *memmem(const void *, size_t, const void *, size_t);
size_t strlen(const char *);
size_t strnlen(const char *, size_t);
char *strcpy(char *, const char *);
char *strncpy(char *, const char *, size_t);
char *stpcpy(char *, const char *);
size_t strlcpy(char *, const char *, size_t);
size_t strlcat(char *, const char *, size_t);
/* a 4-, 8- or 16-byte pattern repeated over len bytes (freemac 1.226, Ferry 0.50.0) */
void memset_pattern4(void *, const void *, size_t);
void memset_pattern8(void *, const void *, size_t);
void memset_pattern16(void *, const void *, size_t);
/* freemac 1.NEXT: served from this system, as VLC finds it */
void *memrchr(const void *, int, size_t);
char *strnstr(const char *, const char *, size_t);
/* C11's bounds-checked memset, which is never optimised away (freemac 1.230) */
int memset_s(void *, size_t, int, size_t);
char *strcat(char *, const char *);
char *strncat(char *, const char *, size_t);
int strcmp(const char *, const char *);
int strncmp(const char *, const char *, size_t);
int strcoll(const char *, const char *);
int strcasecmp(const char *, const char *);
int strncasecmp(const char *, const char *, size_t);
char *strchr(const char *, int);
char *strrchr(const char *, int);
char *strstr(const char *, const char *);
char *strcasestr(const char *, const char *);
char *strdup(const char *);
char *strndup(const char *, size_t);
size_t strspn(const char *, const char *);
size_t strcspn(const char *, const char *);
char *strpbrk(const char *, const char *);
char *strtok(char *, const char *);
char *strtok_r(char *, const char *, char **);
char *strsep(char **, const char *);
char *strerror(int);
int strerror_r(int, char *, size_t);
char *strsignal(int);
void bzero(void *, size_t);
void memset_pattern4(void *, const void *, size_t);
void memset_pattern8(void *, const void *, size_t);
void memset_pattern16(void *, const void *, size_t);
__FERRY_END
#include <strings.h> /* as a Mac's string.h does (VLC: ffsll) */
#endif
