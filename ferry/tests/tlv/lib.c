/* SPDX-License-Identifier: GPL-3.0-or-later
 * A Mac library of the tlv_dylib program's own (built by run.sh with the
 * install name @rpath/libtlvlib.dylib), with thread-local variables the
 * program reaches both through the library's calls and directly. */

__thread int lib_counter = 7;
__thread char lib_tag[16] = "library";
static __thread long lib_hidden;

int lib_bump(void) { return ++lib_counter; }
int *lib_counter_address(void) { return &lib_counter; }
long lib_add(long n) { return lib_hidden += n; }
