/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The Mac's malloc extras, from the malloc(3) and malloc_zone_malloc(3)
 * man pages (freemac 1.221, Ferry 0.45.0). Ferry has one heap, this
 * system's: every zone hands out memory from it, a block's zone is the
 * default zone, and destroying a zone frees the blocks taken from it
 * (src/libc_more.c). */
#ifndef _FERRY_MALLOC_MALLOC_H_
#define _FERRY_MALLOC_MALLOC_H_
#include <_ferry.h>
__FERRY_BEGIN
typedef struct _malloc_zone_t malloc_zone_t;

size_t malloc_size(const void *ptr);
size_t malloc_good_size(size_t size);

malloc_zone_t *malloc_default_zone(void);
malloc_zone_t *malloc_default_purgeable_zone(void);
malloc_zone_t *malloc_create_zone(size_t start_size, unsigned flags);
void malloc_destroy_zone(malloc_zone_t *zone);
malloc_zone_t *malloc_zone_from_ptr(const void *ptr);
void *malloc_zone_malloc(malloc_zone_t *zone, size_t size);
void *malloc_zone_calloc(malloc_zone_t *zone, size_t num_items, size_t size);
void *malloc_zone_valloc(malloc_zone_t *zone, size_t size);
void *malloc_zone_realloc(malloc_zone_t *zone, void *ptr, size_t size);
void *malloc_zone_memalign(malloc_zone_t *zone, size_t alignment, size_t size);
void malloc_zone_free(malloc_zone_t *zone, void *ptr);
void malloc_set_zone_name(malloc_zone_t *zone, const char *name);
const char *malloc_get_zone_name(malloc_zone_t *zone);
size_t malloc_zone_pressure_relief(malloc_zone_t *zone, size_t goal);
/* the list of zones, the default first (freemac 1.264): registering adds a
 * zone at the end, unregistering moves the last zone into its place */
typedef int memory_reader_t(unsigned task, unsigned long address, unsigned long size, void **local_memory);
int malloc_get_all_zones(unsigned task, memory_reader_t reader, unsigned long **addresses, unsigned *count);
void malloc_zone_register(malloc_zone_t *zone);
void malloc_zone_unregister(malloc_zone_t *zone);
__FERRY_END
#endif
