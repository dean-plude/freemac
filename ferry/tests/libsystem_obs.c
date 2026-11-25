/* SPDX-License-Identifier: GPL-3.0-or-later
 * What OBS's libobs asks of libSystem (freemac OBS work): uuid(3), the
 * older task_info flavors its CPU meter adds up, vm_page_size and
 * HOST_VM_INFO through a vm_statistics_t, and simd/base.h's markers. */
#include <mach/mach.h>
#include <simd/base.h>
#include <stdio.h>
#include <string.h>
#include <uuid/uuid.h>

static volatile double sink;

int main(void)
{
    uuid_t a, b, c;
    uuid_string_t s, lower;
    uuid_generate(a);
    uuid_generate_random(b);
    uuid_unparse(a, s);
    uuid_unparse_lower(a, lower);
    int ok = strlen(s) == 36 && s[8] == '-' && s[13] == '-' && s[14] == '4' && s[23] == '-';
    char v = s[19];
    ok = ok && (v == '8' || v == '9' || v == 'A' || v == 'B');
    int upper_ok = 1, lower_ok = 1;
    for (int i = 0; i < 36; i++) {
        if (s[i] >= 'a' && s[i] <= 'f')
            upper_ok = 0;
        if (lower[i] >= 'A' && lower[i] <= 'F')
            lower_ok = 0;
    }
    printf("uuid %s, upper %d, lower %d, different %d\n", ok ? "v4" : "bad", upper_ok, lower_ok,
           uuid_compare(a, b) != 0);
    ok = uuid_parse(lower, c) == 0 && uuid_compare(a, c) == 0;
    printf("parse back %d, bad text %d, ", ok, uuid_parse("not-a-uuid", c));
    uuid_copy(c, a);
    int same = !uuid_compare(a, c);
    uuid_clear(c);
    printf("copy %d, cleared null %d, null %d\n", same, uuid_is_null(c), uuid_is_null(a));

    for (long i = 0; i < 30000000; i++)
        sink += (double)i * 0.5;
    struct task_thread_times_info threads;
    struct task_basic_info_64 basic;
    mach_msg_type_number_t n = TASK_THREAD_TIMES_INFO_COUNT;
    kern_return_t k1 = task_info(mach_task_self(), TASK_THREAD_TIMES_INFO, (task_info_t)&threads, &n);
    int n1 = (int)n;
    n = TASK_BASIC_INFO_64_COUNT;
    kern_return_t k2 = task_info(mach_task_self(), TASK_BASIC_INFO_64, (task_info_t)&basic, &n);
    long long us = (long long)(threads.user_time.seconds + basic.user_time.seconds) * 1000000 +
                   threads.user_time.microseconds + basic.user_time.microseconds;
    printf("thread times %d (%d), basic %d (%d, %zu bytes), cpu time used %d, resident %d\n", k1, n1, k2, (int)n,
           sizeof basic, us > 0, basic.resident_size > 0 && basic.virtual_size >= basic.resident_size);

    vm_statistics_data_t vm;
    vm_statistics_t p = &vm;
    n = HOST_VM_INFO_COUNT;
    kern_return_t k3 = host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)p, &n);
    printf("page %lu (mask %lx, shift %d), vm info %d, free memory %d\n", (unsigned long)vm_page_size,
           (unsigned long)vm_page_mask, vm_page_shift, k3, vm.free_count * vm_page_size > 0);
    printf("simd markers %d\n", SIMD_COMPILER_HAS_REQUIRED_FEATURES);
    return 0;
}
