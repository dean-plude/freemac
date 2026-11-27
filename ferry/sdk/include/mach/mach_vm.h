/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Memory entries and mapping (freemac 1.265, Ferry 0.88.0), from the Mach
 * reference pages and Apple's developer documentation of
 * mach_make_memory_entry_64, mach_vm_map, mach_vm_allocate,
 * mach_vm_deallocate, mach_vm_protect and mach_vm_read. A memory entry is
 * memory that can be mapped more than once, and passed in a message: Ferry
 * keeps it in a memory file. Only the calling task is served. */
#ifndef _FERRY_MACH_VM_H_
#define _FERRY_MACH_VM_H_
#include <mach/vm_map.h>
__FERRY_BEGIN
typedef mach_port_t mem_entry_name_port_t;
typedef mach_port_t memory_object_t;
typedef uint64_t memory_object_size_t;
typedef uint64_t mach_vm_offset_t;
#define MAP_MEM_NAMED_CREATE 0x020000
#define MAP_MEM_NAMED_REUSE 0x080000
#define VM_FLAGS_OVERWRITE 0x4000
#define VM_FLAGS_PURGABLE 0x0002
#define VM_PURGABLE_SET_STATE 0
#define VM_PURGABLE_GET_STATE 1
#define VM_PURGABLE_NONVOLATILE 0
#define VM_PURGABLE_VOLATILE 1
#define VM_PURGABLE_EMPTY 2
#ifndef KERN_INVALID_RIGHT
#define KERN_INVALID_RIGHT 17
#endif
kern_return_t mach_make_memory_entry_64(vm_map_t target_task, memory_object_size_t *size,
                                        memory_object_offset_t offset, vm_prot_t permission,
                                        mach_port_t *object_handle, mem_entry_name_port_t parent_entry);
kern_return_t mach_vm_map(vm_map_t target_task, mach_vm_address_t *address, mach_vm_size_t size,
                          mach_vm_offset_t mask, int flags, mem_entry_name_port_t object,
                          memory_object_offset_t offset, boolean_t copy, vm_prot_t cur_protection,
                          vm_prot_t max_protection, vm_inherit_t inheritance);
kern_return_t mach_vm_allocate(vm_map_t target, mach_vm_address_t *address, mach_vm_size_t size, int flags);
kern_return_t mach_vm_deallocate(vm_map_t target, mach_vm_address_t address, mach_vm_size_t size);
kern_return_t mach_vm_protect(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size,
                              boolean_t set_maximum, vm_prot_t new_protection);
kern_return_t mach_vm_purgable_control(vm_map_t target_task, mach_vm_address_t address, int control, int *state);
kern_return_t mach_vm_read_overwrite(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size,
                                     mach_vm_address_t data, mach_vm_size_t *outsize);
__FERRY_END
#endif
