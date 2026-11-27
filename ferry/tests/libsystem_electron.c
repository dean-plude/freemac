/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Chromium asks of libSystem first, in every Electron app (freemac
 * 1.264, Obsidian): the list of malloc zones, which PartitionAlloc
 * reorders (it registers a zone of its own, unregisters the default zone
 * and registers it again, then checks that its zone is listed first), and
 * vm_region_64 on its own memory. */
#include <mach/mach.h>
#include <malloc/malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static malloc_zone_t *first(unsigned *n)
{
    unsigned long *zones = NULL;
    malloc_get_all_zones(0, NULL, &zones, n);
    return (malloc_zone_t *)zones[0];
}

int main(void)
{
    unsigned n;
    malloc_zone_t *def = first(&n);
    printf("first is the default zone: %s, zones %u\n", def == malloc_default_zone() ? "yes" : "no", n);

    malloc_zone_t *mine = malloc_create_zone(0, 0);
    malloc_set_zone_name(mine, "MyZone");
    first(&n);
    printf("a new zone is listed: zones %u\n", n);
    malloc_zone_unregister(mine);
    first(&n);
    printf("unregistered: zones %u\n", n);

    malloc_zone_register(mine);
    malloc_zone_unregister(def);
    malloc_zone_register(def);
    malloc_zone_t *now = first(&n);
    printf("after the swap the first is mine: %s, zones %u\n", now == mine ? "yes" : "no", n);
    printf("its name: %s\n", malloc_get_zone_name(now));

    /* and memory still comes and goes */
    char *p = malloc(100);
    strcpy(p, "still works");
    printf("%s\n", p);
    free(p);
    malloc_zone_unregister(mine);
    printf("back to the default: %s\n", first(&n) == def ? "yes" : "no");

    /* vm_region_64: the region holding a stack variable, then a heap block */
    int on_stack = 1;
    vm_address_t a = (vm_address_t)&on_stack;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object;
    kern_return_t kr = vm_region_64(mach_task_self(), &a, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info,
                                    &count, &object);
    printf("stack: %d, holds it %s, read-write %s, count %u\n", kr,
           a <= (vm_address_t)&on_stack && (vm_address_t)&on_stack < a + size ? "yes" : "no",
           (info.protection & (VM_PROT_READ | VM_PROT_WRITE)) == (VM_PROT_READ | VM_PROT_WRITE) ? "yes" : "no", count);
    a = 0;
    count = VM_REGION_BASIC_INFO_COUNT_64;
    kr = vm_region_64(mach_task_self(), &a, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    printf("the lowest region: %d, above zero %s\n", kr, a > 0 && size > 0 ? "yes" : "no");
    a = (vm_address_t)-4096;
    count = VM_REGION_BASIC_INFO_COUNT_64;
    kr = vm_region_64(mach_task_self(), &a, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    printf("past the end: %s\n", kr == KERN_INVALID_ADDRESS ? "KERN_INVALID_ADDRESS" : "something");
    return 0;
}
