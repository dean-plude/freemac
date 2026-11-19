#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds each test as an Intel Mac program with ferry-cc, runs it through
# ./ferry and compares what it prints (plus its exit status) with NAME.out.
set -u
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
build="$here/build"
mkdir -p "$build"
export FERRY_SDK="$top/sdk"
pass=0
fail=0
run_one() {
    name=$1; src=$2; expected=$3; shift 3
    exe="$build/$name"
    if ! "$top/sdk/ferry-cc" -O1 -o "$exe" "$src" "$@" 2> "$build/$name.cc.log"; then
        echo "FAIL $name (did not compile)"; sed 's/^/    /' "$build/$name.cc.log"
        fail=$((fail + 1)); return
    fi
    case $name in
        hello*) FERRY_TEST_VALUE=tide "$top/ferry" "$exe" boat > "$build/$name.got" 2> "$build/$name.err" ;;
        system) "$top/ferry" "$exe" -a -b val file > "$build/$name.got" 2> "$build/$name.err" ;;
        *) "$top/ferry" "$exe" > "$build/$name.got" 2> "$build/$name.err" ;;
    esac
    echo "exit=$?" >> "$build/$name.got"
    if diff -u "$expected" "$build/$name.got" > "$build/$name.diff"; then
        echo "ok   $name"; pass=$((pass + 1))
    else
        echo "FAIL $name"; sed 's/^/    /' "$build/$name.diff"; sed 's/^/    stderr: /' "$build/$name.err"
        fail=$((fail + 1))
    fi
}
for t in hello files errors memory signals system; do
    run_one "$t" "$here/$t.c" "$here/$t.out"
done
# A call Ferry doesn't have is left for the loader to find, as a Mac linker
# would with -undefined dynamic_lookup.
run_one unsupported "$here/unsupported.c" "$here/unsupported.out" -Wl,-undefined,dynamic_lookup
# The same programs linked with chained fixups, the newer Mach-O layout.
for t in hello files; do
    run_one "${t}_chained" "$here/$t.c" "$here/$t.out" -Wl,-fixup_chains
done
# The unsupported program must also say what was missing.
if grep -q "pthread_yield_np" "$build/unsupported.err" 2>/dev/null; then
    echo "ok   unsupported message"; pass=$((pass + 1))
else
    echo "FAIL unsupported message"; fail=$((fail + 1))
fi
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
