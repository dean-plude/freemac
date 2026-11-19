/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _STDLIB_H_
#define _STDLIB_H_
#include <_ferry.h>
__FERRY_BEGIN
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 0x7fffffff
#define MB_CUR_MAX 1
typedef struct { int quot, rem; } div_t;
typedef struct { long quot, rem; } ldiv_t;
void *malloc(size_t);
void *calloc(size_t, size_t);
void *realloc(void *, size_t);
void *reallocf(void *, size_t);
void free(void *);
int posix_memalign(void **, size_t, size_t);
void *aligned_alloc(size_t, size_t);
void *valloc(size_t);
size_t malloc_size(const void *);
void abort(void) __attribute__((noreturn));
void exit(int) __attribute__((noreturn));
void _Exit(int) __attribute__((noreturn));
int atexit(void (*)(void));
int system(const char *);
char *getenv(const char *);
int setenv(const char *, const char *, int);
int unsetenv(const char *);
int putenv(char *);
const char *getprogname(void);
int atoi(const char *);
long atol(const char *);
long long atoll(const char *);
double atof(const char *);
long strtol(const char *, char **, int);
unsigned long strtoul(const char *, char **, int);
long long strtoll(const char *, char **, int);
unsigned long long strtoull(const char *, char **, int);
double strtod(const char *, char **);
float strtof(const char *, char **);
int abs(int);
long labs(long);
long long llabs(long long);
div_t div(int, int);
ldiv_t ldiv(long, long);
int rand(void);
void srand(unsigned);
long random(void);
void srandom(unsigned);
uint32_t arc4random(void);
uint32_t arc4random_uniform(uint32_t);
void arc4random_buf(void *, size_t);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *));
void *bsearch(const void *, const void *, size_t, size_t, int (*)(const void *, const void *));
int mkstemp(char *);
char *mkdtemp(char *);
char *realpath(const char *, char *);
__FERRY_END
#endif
