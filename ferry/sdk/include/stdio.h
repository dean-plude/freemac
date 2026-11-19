/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _STDIO_H_
#define _STDIO_H_
#include <_ferry.h>
#include <stdarg.h>
__FERRY_BEGIN
typedef struct __sFILE FILE;
extern FILE *__stdinp, *__stdoutp, *__stderrp;
#define stdin __stdinp
#define stdout __stdoutp
#define stderr __stderrp
#define EOF (-1)
#define BUFSIZ 1024
#define FILENAME_MAX 1024
#define L_tmpnam 1024
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2
FILE *fopen(const char *, const char *);
FILE *fdopen(int, const char *);
FILE *freopen(const char *, const char *, FILE *);
FILE *tmpfile(void);
FILE *popen(const char *, const char *);
FILE *fmemopen(void *, size_t, const char *);
FILE *open_memstream(char **, size_t *);
int fclose(FILE *);
int pclose(FILE *);
int fflush(FILE *);
int printf(const char *, ...) __attribute__((format(printf, 1, 2)));
int fprintf(FILE *, const char *, ...) __attribute__((format(printf, 2, 3)));
int sprintf(char *, const char *, ...) __attribute__((format(printf, 2, 3)));
int snprintf(char *, size_t, const char *, ...) __attribute__((format(printf, 3, 4)));
int dprintf(int, const char *, ...) __attribute__((format(printf, 2, 3)));
int asprintf(char **, const char *, ...) __attribute__((format(printf, 2, 3)));
int vprintf(const char *, va_list);
int vfprintf(FILE *, const char *, va_list);
int vsprintf(char *, const char *, va_list);
int vsnprintf(char *, size_t, const char *, va_list);
int vasprintf(char **, const char *, va_list);
int scanf(const char *, ...);
int fscanf(FILE *, const char *, ...);
int sscanf(const char *, const char *, ...);
int vfscanf(FILE *, const char *, va_list);
int vsscanf(const char *, const char *, va_list);
int fputc(int, FILE *);
int putc(int, FILE *);
int putchar(int);
int fputs(const char *, FILE *);
int puts(const char *);
int fgetc(FILE *);
int getc(FILE *);
int getchar(void);
int ungetc(int, FILE *);
char *fgets(char *, int, FILE *);
char *fgetln(FILE *, size_t *);
ssize_t getline(char **, size_t *, FILE *);
ssize_t getdelim(char **, size_t *, int, FILE *);
size_t fread(void *, size_t, size_t, FILE *);
size_t fwrite(const void *, size_t, size_t, FILE *);
int fseek(FILE *, long, int);
int fseeko(FILE *, off_t, int);
long ftell(FILE *);
off_t ftello(FILE *);
void rewind(FILE *);
int fgetpos(FILE *, fpos_t *);
int fsetpos(FILE *, const fpos_t *);
int feof(FILE *);
int ferror(FILE *);
void clearerr(FILE *);
int fileno(FILE *);
int setvbuf(FILE *, char *, int, size_t);
void setbuf(FILE *, char *);
void setbuffer(FILE *, char *, int);
int setlinebuf(FILE *);
void flockfile(FILE *);
void funlockfile(FILE *);
int remove(const char *);
int rename(const char *, const char *);
void perror(const char *);
__FERRY_END
#endif
