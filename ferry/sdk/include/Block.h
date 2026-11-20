/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: copying and releasing blocks. Written for freemac from the
 * public block ABI; not Apple's header. */
#ifndef _FERRY_BLOCK_H_
#define _FERRY_BLOCK_H_
#include <_ferry.h>
__FERRY_BEGIN
void *_Block_copy(const void *block);
void _Block_release(const void *block);
void _Block_object_assign(void *dest, const void *object, const int flags);
void _Block_object_dispose(const void *object, const int flags);
extern void *_NSConcreteGlobalBlock[32];
extern void *_NSConcreteStackBlock[32];
__FERRY_END
#define Block_copy(block) ((__typeof__(block))_Block_copy((const void *)(block)))
#define Block_release(block) _Block_release((const void *)(block))
#endif
