/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * A task's memory (freemac 1.232, Ferry 0.56.0), from the Mach reference
 * pages for vm_allocate, vm_deallocate and vm_remap. Only the calling task
 * is served, and vm_remap only as a copy, as Qt's resources use it.
 * vm_region_64 and mach_vm_region report a region's basic information
 * (freemac 1.264), as Apple's developer documentation of
 * vm_region_basic_info_64 lays it out. */
#ifndef _FERRY_MACH_VM_MAP_H_
#define _FERRY_MACH_VM_MAP_H_
#include <mach/mach.h>
__FERRY_BEGIN
typedef uintptr_t vm_address_t;
typedef uintptr_t vm_offset_t;
typedef int vm_prot_t;
typedef unsigned int vm_inherit_t;
typedef mach_port_t vm_map_t;
#define VM_PROT_NONE 0x00
#define VM_PROT_READ 0x01
#define VM_PROT_WRITE 0x02
#define VM_PROT_EXECUTE 0x04
#define VM_PROT_DEFAULT (VM_PROT_READ | VM_PROT_WRITE)
#define VM_PROT_ALL (VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)
#define VM_INHERIT_SHARE 0
#define VM_INHERIT_COPY 1
#define VM_INHERIT_NONE 2
#define VM_INHERIT_DEFAULT VM_INHERIT_COPY
#define VM_FLAGS_FIXED 0x0000
#define VM_FLAGS_ANYWHERE 0x0001
kern_return_t vm_allocate(vm_map_t target, vm_address_t *address, vm_size_t size, int flags);
kern_return_t vm_deallocate(vm_map_t target, vm_address_t address, vm_size_t size);
kern_return_t vm_remap(vm_map_t target, vm_address_t *target_address, vm_size_t size, vm_address_t mask,
                       int flags, vm_map_t src_task, vm_address_t src_address, boolean_t copy,
                       vm_prot_t *cur_protection, vm_prot_t *max_protection, vm_inherit_t inheritance);

#ifndef KERN_INVALID_ADDRESS
#define KERN_INVALID_ADDRESS 1
#endif
typedef int *vm_region_info_t;
typedef int *vm_region_info_64_t;
typedef int vm_region_flavor_t;
typedef int vm_behavior_t;
typedef unsigned long long memory_object_offset_t;
typedef uint32_t vm32_object_id_t;
typedef uint64_t mach_vm_address_t;
#define VM_REGION_BASIC_INFO_64 9
#define VM_REGION_BASIC_INFO 10
#pragma pack(push, 4)
struct vm_region_basic_info_64 {
    vm_prot_t protection;
    vm_prot_t max_protection;
    vm_inherit_t inheritance;
    boolean_t shared;
    boolean_t reserved;
    memory_object_offset_t offset;
    vm_behavior_t behavior;
    unsigned short user_wired_count;
};
struct vm_region_basic_info {
    vm_prot_t protection;
    vm_prot_t max_protection;
    vm_inherit_t inheritance;
    boolean_t shared;
    boolean_t reserved;
    uint32_t offset;
    vm_behavior_t behavior;
    unsigned short user_wired_count;
};
#pragma pack(pop)
typedef struct vm_region_basic_info_64 *vm_region_basic_info_64_t;
typedef struct vm_region_basic_info_64 vm_region_basic_info_data_64_t;
typedef struct vm_region_basic_info *vm_region_basic_info_t;
typedef struct vm_region_basic_info vm_region_basic_info_data_t;
#define VM_REGION_BASIC_INFO_COUNT_64 ((mach_msg_type_number_t)(sizeof(vm_region_basic_info_data_64_t) / sizeof(int)))
#define VM_REGION_BASIC_INFO_COUNT ((mach_msg_type_number_t)(sizeof(vm_region_basic_info_data_t) / sizeof(int)))
kern_return_t vm_region_64(vm_map_t target_task, vm_address_t *address, vm_size_t *size, vm_region_flavor_t flavor,
                           vm_region_info_t info, mach_msg_type_number_t *infoCnt, mach_port_t *object_name);
kern_return_t vm_region(vm_map_t target_task, vm_address_t *address, vm_size_t *size, vm_region_flavor_t flavor,
                        vm_region_info_t info, mach_msg_type_number_t *infoCnt, mach_port_t *object_name);
kern_return_t mach_vm_region(vm_map_t target_task, mach_vm_address_t *address, mach_vm_size_t *size,
                             vm_region_flavor_t flavor, vm_region_info_t info, mach_msg_type_number_t *infoCnt,
                             mach_port_t *object_name);
__FERRY_END
#endif
