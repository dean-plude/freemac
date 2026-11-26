/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: dispatch data objects (freemac 1.232, Ferry 0.56.0), written
 * for freemac from Apple's public documentation of libdispatch; not
 * Apple's header. A data object is an immutable run of bytes, which here is
 * always kept in one piece, so a map or an apply sees it as one region
 * (ferry/src/objc/dispatch_io.c). Included by <dispatch/dispatch.h>. */
#ifndef _FERRY_DISPATCH_DATA_H_
#define _FERRY_DISPATCH_DATA_H_
#include <dispatch/dispatch.h>
__FERRY_BEGIN

/* the empty data object, a global one, as on a Mac */
extern struct dispatch_data_s _dispatch_data_empty;
#define dispatch_data_empty ((dispatch_data_t)(void *)&_dispatch_data_empty)

#if __BLOCKS__
/* What happens to the bytes a data object is made from: DEFAULT copies
 * them; FREE takes them and frees them; MUNMAP takes them and unmaps them;
 * any other block is called on the queue given once they aren't needed. */
#define DISPATCH_DATA_DESTRUCTOR_DEFAULT NULL
extern const dispatch_block_t _dispatch_data_destructor_free;
extern const dispatch_block_t _dispatch_data_destructor_munmap;
#define DISPATCH_DATA_DESTRUCTOR_FREE (_dispatch_data_destructor_free)
#define DISPATCH_DATA_DESTRUCTOR_MUNMAP (_dispatch_data_destructor_munmap)

typedef bool (^dispatch_data_applier_t)(dispatch_data_t region, size_t offset, const void *buffer, size_t size);

DISPATCH_RETURNS_RETAINED dispatch_data_t dispatch_data_create(const void *buffer, size_t size,
                                                               dispatch_queue_t queue, dispatch_block_t destructor);
bool dispatch_data_apply(dispatch_data_t data, __attribute__((noescape)) dispatch_data_applier_t applier);
#endif
size_t dispatch_data_get_size(dispatch_data_t data);
DISPATCH_RETURNS_RETAINED dispatch_data_t dispatch_data_create_map(dispatch_data_t data, const void **buffer_ptr,
                                                                   size_t *size_ptr);
DISPATCH_RETURNS_RETAINED dispatch_data_t dispatch_data_create_concat(dispatch_data_t data1, dispatch_data_t data2);
DISPATCH_RETURNS_RETAINED dispatch_data_t dispatch_data_create_subrange(dispatch_data_t data, size_t offset,
                                                                        size_t length);
DISPATCH_RETURNS_RETAINED dispatch_data_t dispatch_data_copy_region(dispatch_data_t data, size_t location,
                                                                    size_t *offset_ptr);

__FERRY_END
#endif
