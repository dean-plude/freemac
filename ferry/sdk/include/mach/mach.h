/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The Mach calls programs make for memory and processor figures, from the
 * Mach reference pages (host_statistics, host_info, host_page_size,
 * task_info). Only these are served. */
#ifndef _FERRY_MACH_H_
#define _FERRY_MACH_H_
#include <_ferry.h>
#include <mach/mach_time.h>
#include <mach/boolean.h>
#include <mach/machine.h>
#include <mach/message.h>
__FERRY_BEGIN
typedef int kern_return_t;
typedef uint32_t natural_t;
typedef int32_t integer_t;
typedef natural_t mach_port_t;
#define MACH_PORT_NULL ((mach_port_t)0) /* freemac 1.NEXT (VLC) */
typedef mach_port_t host_t;
typedef mach_port_t task_t;
typedef mach_port_t ipc_space_t;
typedef mach_port_t mach_port_name_t;
typedef mach_port_t host_name_port_t;
typedef uintptr_t vm_size_t;
typedef uint64_t mach_vm_size_t;
typedef int host_flavor_t;
typedef int task_flavor_t;
typedef integer_t *host_info_t;
typedef integer_t *host_info64_t;
typedef integer_t *task_info_t;
typedef natural_t mach_msg_type_number_t;
typedef integer_t cpu_type_t, cpu_subtype_t, cpu_threadtype_t;

#define KERN_SUCCESS 0
#define KERN_INVALID_ARGUMENT 4
#define KERN_FAILURE 5

extern mach_port_t mach_task_self_;
#define mach_task_self() mach_task_self_
#define current_task() mach_task_self()
mach_port_t mach_host_self(void);
kern_return_t mach_port_deallocate(ipc_space_t task, mach_port_name_t name);
kern_return_t host_page_size(host_t host, vm_size_t *size);

#define HOST_BASIC_INFO 1
#define HOST_VM_INFO 2
#define HOST_CPU_LOAD_INFO 3
#define HOST_VM_INFO64 4

#define CPU_STATE_USER 0
#define CPU_STATE_SYSTEM 1
#define CPU_STATE_IDLE 2
#define CPU_STATE_NICE 3
#define CPU_STATE_MAX 4

struct host_basic_info {
    integer_t max_cpus;
    integer_t avail_cpus;
    natural_t memory_size;
    cpu_type_t cpu_type;
    cpu_subtype_t cpu_subtype;
    cpu_threadtype_t cpu_threadtype;
    integer_t physical_cpu;
    integer_t physical_cpu_max;
    integer_t logical_cpu;
    integer_t logical_cpu_max;
    uint64_t max_mem;
} __attribute__((packed, aligned(4)));
typedef struct host_basic_info host_basic_info_data_t;
#define HOST_BASIC_INFO_COUNT ((mach_msg_type_number_t)(sizeof(host_basic_info_data_t) / sizeof(integer_t)))

struct host_cpu_load_info { natural_t cpu_ticks[CPU_STATE_MAX]; };
typedef struct host_cpu_load_info host_cpu_load_info_data_t;
#define HOST_CPU_LOAD_INFO_COUNT ((mach_msg_type_number_t)(sizeof(host_cpu_load_info_data_t) / sizeof(integer_t)))

struct vm_statistics {
    natural_t free_count, active_count, inactive_count, wire_count, zero_fill_count, reactivations, pageins,
        pageouts, faults, cow_faults, lookups, hits, purgeable_count, purges, speculative_count;
};
typedef struct vm_statistics vm_statistics_data_t;
#define HOST_VM_INFO_COUNT ((mach_msg_type_number_t)(sizeof(vm_statistics_data_t) / sizeof(integer_t)))

struct vm_statistics64 {
    natural_t free_count, active_count, inactive_count, wire_count;
    uint64_t zero_fill_count, reactivations, pageins, pageouts, faults, cow_faults, lookups, hits, purges;
    natural_t purgeable_count, speculative_count;
    uint64_t decompressions, compressions, swapins, swapouts;
    natural_t compressor_page_count, throttled_count, external_page_count, internal_page_count;
    uint64_t total_uncompressed_pages_in_compressor;
} __attribute__((aligned(8)));
typedef struct vm_statistics64 vm_statistics64_data_t;
#define HOST_VM_INFO64_COUNT ((mach_msg_type_number_t)(sizeof(vm_statistics64_data_t) / sizeof(integer_t)))

kern_return_t host_info(host_t host, host_flavor_t flavor, host_info_t info, mach_msg_type_number_t *count);
kern_return_t host_statistics(host_t host, host_flavor_t flavor, host_info_t info, mach_msg_type_number_t *count);
kern_return_t host_statistics64(host_t host, host_flavor_t flavor, host_info64_t info,
                                mach_msg_type_number_t *count);

typedef struct { integer_t seconds, microseconds; } time_value_t;
#define MACH_TASK_BASIC_INFO 20
struct mach_task_basic_info {
    mach_vm_size_t virtual_size;
    mach_vm_size_t resident_size;
    mach_vm_size_t resident_size_max;
    time_value_t user_time;
    time_value_t system_time;
    integer_t policy;
    integer_t suspend_count;
} __attribute__((packed, aligned(4)));
typedef struct mach_task_basic_info mach_task_basic_info_data_t;
#define MACH_TASK_BASIC_INFO_COUNT ((mach_msg_type_number_t)(sizeof(mach_task_basic_info_data_t) / sizeof(natural_t)))
kern_return_t task_info(task_t task, task_flavor_t flavor, task_info_t info, mach_msg_type_number_t *count);
__FERRY_END
#endif
