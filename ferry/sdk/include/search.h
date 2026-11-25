/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Binary search trees and linear search (freemac 1.NEXT, VLC). */
#ifndef _FERRY_SEARCH_H_
#define _FERRY_SEARCH_H_
#include <_ferry.h>
#include <sys/types.h>
__FERRY_BEGIN
typedef enum { preorder, postorder, endorder, leaf } VISIT;
void *tsearch(const void *, void **, int (*)(const void *, const void *));
void *tfind(const void *, void *const *, int (*)(const void *, const void *));
void *tdelete(const void *__restrict, void **__restrict, int (*)(const void *, const void *));
void twalk(const void *, void (*)(const void *, VISIT, int));
void *lsearch(const void *, void *, size_t *, size_t, int (*)(const void *, const void *));
void *lfind(const void *, const void *, size_t *, size_t, int (*)(const void *, const void *));
__FERRY_END
#endif
