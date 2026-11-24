/* SPDX-License-Identifier: GPL-3.0-or-later
 * The system's figures as a Mac program asks for them: sysctl by name and
 * by number, a process's kinfo_proc and arguments, libproc, the Mach host
 * and task calls, and getattrlist. Written from the sysctl(3),
 * getattrlist(2) and Mach reference pages. Only checks are printed (does
 * it agree with uname, sysconf, stat...), never the machine's own values,
 * so the output is the same on every machine. */
#include <dirent.h>
#include <errno.h>
#include <libproc.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

_Static_assert(sizeof(struct kinfo_proc) == 648, "kinfo_proc is 648 bytes");
_Static_assert(offsetof(struct kinfo_proc, kp_proc.p_flag) == 32, "p_flag");
_Static_assert(offsetof(struct kinfo_proc, kp_proc.p_pid) == 40, "p_pid");
_Static_assert(offsetof(struct kinfo_proc, kp_proc.p_comm) == 243, "p_comm");
_Static_assert(offsetof(struct kinfo_proc, kp_eproc.e_ppid) == 296 + 264, "e_ppid");
_Static_assert(sizeof(vm_statistics64_data_t) == 152, "vm_statistics64");
_Static_assert(sizeof(struct mach_task_basic_info) == 48, "mach_task_basic_info");

static const char *yes(int ok) { return ok ? "yes" : "NO"; }

static const char *err_name(int e)
{
    switch (e) {
    case 0: return "0";
    case ENOMEM: return "ENOMEM";
    case ENOENT: return "ENOENT";
    case EPERM: return "EPERM";
    case EINVAL: return "EINVAL";
    case EISDIR: return "EISDIR";
    default: return "other";
    }
}

static int string_by_name(const char *name, char *buf, size_t size)
{
    size_t len = size;
    return sysctlbyname(name, buf, &len, NULL, 0);
}

static long long number_by_name(const char *name)
{
    long long v = 0;
    size_t len = sizeof v;
    if (sysctlbyname(name, &v, &len, NULL, 0) != 0)
        return -1;
    return len == 4 ? (long long)(int)v : v;
}

static void cpuid(unsigned leaf, unsigned r[4])
{
    __asm__ volatile("cpuid" : "=a"(r[0]), "=b"(r[1]), "=c"(r[2]), "=d"(r[3]) : "a"(leaf), "c"(0));
}

static void trim(char *s)
{
    char *p = s;
    while (*p == ' ')
        p++;
    memmove(s, p, strlen(p) + 1);
    size_t n = strlen(s);
    while (n && s[n - 1] == ' ')
        s[--n] = 0;
}

static void names(void)
{
    char buf[1024], other[1024];
    struct utsname u;
    uname(&u);

    string_by_name("kern.ostype", buf, sizeof buf);
    printf("kern.ostype: %s, matches uname: %s\n", buf, yes(!strcmp(buf, u.sysname)));
    string_by_name("kern.osrelease", buf, sizeof buf);
    printf("kern.osrelease: %s, matches uname: %s\n", buf, yes(!strcmp(buf, u.release)));
    string_by_name("kern.version", buf, sizeof buf);
    printf("kern.version matches uname: %s, starts \"Darwin Kernel Version %s:\": %s\n",
           yes(!strcmp(buf, u.version)), u.release,
           yes(!strncmp(buf, "Darwin Kernel Version ", 22) && !strncmp(buf + 22, u.release, strlen(u.release)) &&
               buf[22 + strlen(u.release)] == ':'));
    string_by_name("kern.osproductversion", buf, sizeof buf);
    printf("kern.osproductversion: %s\n", buf);
    string_by_name("kern.osversion", buf, sizeof buf);
    printf("kern.osversion: %s\n", buf);
    string_by_name("hw.machine", buf, sizeof buf);
    printf("hw.machine: %s, matches uname: %s\n", buf, yes(!strcmp(buf, u.machine)));
    string_by_name("hw.model", buf, sizeof buf);
    printf("hw.model: %s\n", buf);
    string_by_name("kern.hostname", buf, sizeof buf);
    gethostname(other, sizeof other);
    printf("kern.hostname matches gethostname and uname: %s\n", yes(!strcmp(buf, other) && !strcmp(buf, u.nodename)));

    long long ncpu = number_by_name("hw.ncpu"), active = number_by_name("hw.activecpu");
    long long physical = number_by_name("hw.physicalcpu"), logical = number_by_name("hw.logicalcpu");
    printf("hw.ncpu matches sysconf: %s\n", yes(ncpu == sysconf(_SC_NPROCESSORS_CONF)));
    printf("hw.activecpu matches sysconf: %s\n", yes(active == sysconf(_SC_NPROCESSORS_ONLN)));
    printf("hw.logicalcpu is hw.activecpu: %s, hw.logicalcpu_max is hw.ncpu: %s\n", yes(logical == active),
           yes(number_by_name("hw.logicalcpu_max") == ncpu));
    printf("hw.physicalcpu between 1 and hw.ncpu: %s\n", yes(physical >= 1 && physical <= ncpu));
    printf("machdep.cpu.core_count is hw.physicalcpu: %s, thread_count is hw.ncpu: %s\n",
           yes(number_by_name("machdep.cpu.core_count") == physical),
           yes(number_by_name("machdep.cpu.thread_count") == ncpu));
    long long mem = number_by_name("hw.memsize");
    printf("hw.memsize matches sysconf: %s\n",
           yes(mem == (long long)sysconf(_SC_PHYS_PAGES) * sysconf(_SC_PAGESIZE)));
    printf("hw.pagesize matches getpagesize: %s\n", yes(number_by_name("hw.pagesize") == getpagesize()));
    int small = 0;
    size_t len = sizeof small;
    int rc = sysctlbyname("hw.pagesize", &small, &len, NULL, 0);
    printf("hw.pagesize read into an int: %s\n", yes(rc == 0 && small == getpagesize()));
    long long line = number_by_name("hw.cachelinesize");
    printf("hw.cachelinesize is a power of two: %s\n", yes(line > 0 && (line & (line - 1)) == 0));
    printf("hw.byteorder: %lld\n", number_by_name("hw.byteorder"));
    printf("hw.cpu64bit_capable: %lld, hw.optional.x86_64: %lld, hw.optional.sse2: %lld\n",
           number_by_name("hw.cpu64bit_capable"), number_by_name("hw.optional.x86_64"),
           number_by_name("hw.optional.sse2"));
    printf("sysctl.proc_translated: %lld\n", number_by_name("sysctl.proc_translated"));

    unsigned r[4];
    char brand[49] = "";
    cpuid(0x80000000, r);
    if (r[0] >= 0x80000004) {
        for (unsigned i = 0; i < 3; i++) {
            cpuid(0x80000002 + i, r);
            memcpy(brand + 16 * i, r, 16);
        }
        brand[48] = 0;
        trim(brand);
    }
    string_by_name("machdep.cpu.brand_string", buf, sizeof buf);
    printf("machdep.cpu.brand_string matches cpuid: %s\n", yes(!brand[0] || !strcmp(buf, brand)));
    cpuid(0, r);
    char vendor[13];
    memcpy(vendor, &r[1], 4);
    memcpy(vendor + 4, &r[3], 4);
    memcpy(vendor + 8, &r[2], 4);
    vendor[12] = 0;
    string_by_name("machdep.cpu.vendor", buf, sizeof buf);
    printf("machdep.cpu.vendor matches cpuid: %s\n", yes(!strcmp(buf, vendor)));

    struct timeval boot, now;
    len = sizeof boot;
    rc = sysctlbyname("kern.boottime", &boot, &len, NULL, 0);
    gettimeofday(&now, NULL);
    printf("kern.boottime: %s bytes, in the past: %s\n", len == sizeof boot ? "16" : "wrong",
           yes(rc == 0 && boot.tv_sec > 0 && boot.tv_sec <= now.tv_sec));
}

static void rules(void)
{
    char buf[64];
    size_t len = 0;
    int rc = sysctlbyname("kern.osproductversion", NULL, &len, NULL, 0);
    printf("NULL buffer gives the size: %s\n", yes(rc == 0 && len == strlen("14.7") + 1));
    len = 3;
    memset(buf, 'x', sizeof buf);
    rc = sysctlbyname("kern.osproductversion", buf, &len, NULL, 0);
    printf("buffer too small: %s, the start copied: %s\n", err_name(rc ? errno : 0), yes(!memcmp(buf, "14.", 3)));
    len = sizeof buf;
    rc = sysctlbyname("kern.no_such_name", buf, &len, NULL, 0);
    printf("unknown name: %s\n", err_name(rc ? errno : 0));
    int v = 5;
    len = sizeof buf;
    rc = sysctlbyname("hw.ncpu", buf, &len, &v, sizeof v);
    printf("setting a value: %s\n", err_name(rc ? errno : 0));

    int mib[CTL_MAXNAME];
    size_t count = CTL_MAXNAME;
    rc = sysctlnametomib("kern.osrelease", mib, &count);
    printf("sysctlnametomib kern.osrelease: %d.%d (%zu numbers)\n", mib[0], mib[1], count);
    count = CTL_MAXNAME;
    sysctlnametomib("hw.memsize", mib, &count);
    printf("sysctlnametomib hw.memsize: %d.%d (%zu numbers)\n", mib[0], mib[1], count);
    count = 1;
    rc = sysctlnametomib("hw.memsize", mib, &count);
    printf("sysctlnametomib with too little room: %s\n", err_name(rc ? errno : 0));
    count = CTL_MAXNAME;
    rc = sysctlnametomib("no.such.name", mib, &count);
    printf("sysctlnametomib of an unknown name: %s\n", err_name(rc ? errno : 0));

    char a[64], b[64];
    count = CTL_MAXNAME;
    sysctlnametomib("kern.osproductversion", mib, &count);
    size_t la = sizeof a, lb = sizeof b;
    sysctl(mib, (unsigned)count, a, &la, NULL, 0);
    sysctlbyname("kern.osproductversion", b, &lb, NULL, 0);
    printf("by the numbers from sysctlnametomib, the same answer: %s\n", yes(la == lb && !strcmp(a, b)));
    int byname[2] = {CTL_KERN, KERN_OSRELEASE};
    la = sizeof a;
    lb = sizeof b;
    sysctl(byname, 2, a, &la, NULL, 0);
    sysctlbyname("kern.osrelease", b, &lb, NULL, 0);
    printf("CTL_KERN.KERN_OSRELEASE is kern.osrelease: %s\n", yes(!strcmp(a, b)));
    int hwmem[2] = {CTL_HW, HW_MEMSIZE};
    uint64_t m = 0;
    la = sizeof m;
    sysctl(hwmem, 2, &m, &la, NULL, 0);
    printf("CTL_HW.HW_MEMSIZE is hw.memsize: %s\n", yes((long long)m == number_by_name("hw.memsize")));
    int unknown[2] = {CTL_HW, 9999};
    la = sizeof a;
    rc = sysctl(unknown, 2, a, &la, NULL, 0);
    printf("unknown number: %s\n", err_name(rc ? errno : 0));
}

static void process(const char *argv0, int argc)
{
    struct kinfo_proc k;
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    size_t len = sizeof k;
    memset(&k, 0, sizeof k);
    int rc = sysctl(mib, 4, &k, &len, NULL, 0);
    printf("kinfo_proc: %s, %zu bytes\n", rc == 0 ? "found" : "missing", len);
    printf("p_pid is getpid: %s, e_ppid is getppid: %s\n", yes(k.kp_proc.p_pid == getpid()),
           yes(k.kp_eproc.e_ppid == getppid()));
    const char *base = strrchr(argv0, '/') ? strrchr(argv0, '/') + 1 : argv0;
    printf("p_comm is the program's name: %s\n", yes(!strncmp(k.kp_proc.p_comm, base, MAXCOMLEN)));
    printf("P_TRACED: %s, P_LP64: %s\n", k.kp_proc.p_flag & P_TRACED ? "set" : "clear",
           k.kp_proc.p_flag & P_LP64 ? "set" : "clear");
    printf("cr_uid is getuid: %s, p_ruid is getuid: %s\n", yes(k.kp_eproc.e_ucred.cr_uid == getuid()),
           yes(k.kp_eproc.e_pcred.p_ruid == getuid()));
    struct timeval now;
    gettimeofday(&now, NULL);
    printf("p_starttime in the past: %s\n",
           yes(k.kp_proc.p_starttime.tv_sec > 0 && k.kp_proc.p_starttime.tv_sec <= now.tv_sec));

    mib[3] = getppid();
    len = sizeof k;
    rc = sysctl(mib, 4, &k, &len, NULL, 0);
    printf("parent's kinfo_proc: %s, p_pid is getppid: %s\n", rc == 0 && len == sizeof k ? "found" : "missing",
           yes(k.kp_proc.p_pid == getppid()));
    mib[3] = 0x7ffffff0;
    len = sizeof k;
    rc = sysctl(mib, 4, &k, &len, NULL, 0);
    printf("a pid that doesn't exist: returns %d, %zu bytes\n", rc, len);
    len = 0;
    mib[3] = getpid();
    rc = sysctl(mib, 4, NULL, &len, NULL, 0);
    printf("size of kinfo_proc asked with a NULL buffer: %zu\n", len);

    char exe[4096];
    uint32_t exelen = sizeof exe;
    _NSGetExecutablePath(exe, &exelen);
    static char args[1 << 18];
    int amib[3] = {CTL_KERN, KERN_PROCARGS2, getpid()};
    len = sizeof args;
    rc = sysctl(amib, 3, args, &len, NULL, 0);
    int count;
    memcpy(&count, args, 4);
    const char *path = args + 4;
    const char *p = path + strlen(path);
    while (p < args + len && !*p)
        p++;
    printf("KERN_PROCARGS2: argc matches: %s, program path matches: %s, argv[0] matches: %s\n",
           yes(rc == 0 && count == argc), yes(!strcmp(path, exe)), yes(!strcmp(p, argv0)));

    char pidpath[PROC_PIDPATHINFO_MAXSIZE], real[4096];
    int n = proc_pidpath(getpid(), pidpath, sizeof pidpath);
    printf("proc_pidpath is _NSGetExecutablePath, links resolved: %s\n",
           yes(n > 0 && realpath(exe, real) && !strcmp(pidpath, real) && n == (int)strlen(real)));
    n = proc_pidpath(getpid(), pidpath, 16);
    printf("proc_pidpath with a small buffer: %d, %s\n", n, err_name(errno));
    n = proc_pidpath(getppid(), pidpath, sizeof pidpath);
    printf("proc_pidpath of the parent: %s\n", n > 0 && pidpath[0] == '/' ? "found" : "missing");
    char name[64];
    n = proc_name(getpid(), name, sizeof name);
    printf("proc_name is the program's name: %s\n", yes(n > 0 && !strcmp(name, base)));
}

static void mach(void)
{
    long long mem = number_by_name("hw.memsize"), ncpu = number_by_name("hw.ncpu");
    mach_port_t host = mach_host_self();
    vm_size_t page = 0;
    kern_return_t kr = host_page_size(host, &page);
    printf("host_page_size matches getpagesize: %s\n", yes(kr == KERN_SUCCESS && page == (vm_size_t)getpagesize()));

    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kr = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count);
    unsigned long long pages = (unsigned long long)vm.free_count + vm.active_count + vm.inactive_count + vm.wire_count;
    printf("host_statistics64: %s, count %u, pages within hw.memsize: %s\n", kr == KERN_SUCCESS ? "ok" : "failed",
           count, yes(pages > 0 && pages <= (unsigned long long)mem / page));
    count = 2;
    kr = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count);
    printf("host_statistics64 with too little room: %s\n", kr == KERN_SUCCESS ? "ok" : "refused");

    vm_statistics_data_t vm32;
    count = HOST_VM_INFO_COUNT;
    kr = host_statistics(host, HOST_VM_INFO, (host_info_t)&vm32, &count);
    printf("host_statistics HOST_VM_INFO: %s, count %u\n", kr == KERN_SUCCESS ? "ok" : "failed", count);
    host_cpu_load_info_data_t load;
    count = HOST_CPU_LOAD_INFO_COUNT;
    kr = host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&load, &count);
    printf("host_statistics HOST_CPU_LOAD_INFO: %s, count %u, some ticks: %s\n", kr == KERN_SUCCESS ? "ok" : "failed",
           count, yes(load.cpu_ticks[CPU_STATE_USER] + load.cpu_ticks[CPU_STATE_SYSTEM] + load.cpu_ticks[CPU_STATE_IDLE] > 0));

    host_basic_info_data_t basic;
    count = HOST_BASIC_INFO_COUNT;
    kr = host_info(host, HOST_BASIC_INFO, (host_info_t)&basic, &count);
    printf("host_info HOST_BASIC_INFO: %s, count %u, max_cpus is hw.ncpu: %s, max_mem is hw.memsize: %s\n",
           kr == KERN_SUCCESS ? "ok" : "failed", count, yes(basic.max_cpus == ncpu),
           yes((long long)basic.max_mem == mem));

    mach_task_basic_info_data_t task;
    count = MACH_TASK_BASIC_INFO_COUNT;
    kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&task, &count);
    printf("task_info MACH_TASK_BASIC_INFO: %s, count %u, resident within virtual: %s\n",
           kr == KERN_SUCCESS ? "ok" : "failed", count,
           yes(task.resident_size > 0 && task.resident_size <= task.virtual_size));
    printf("mach_port_deallocate: %s\n", mach_port_deallocate(mach_task_self(), host) == KERN_SUCCESS ? "ok" : "failed");
}

struct file_attrs {
    uint32_t length;
    attribute_set_t returned;
    attrreference_t name;
    fsobj_type_t type;
    struct timespec modified;
    attrreference_t fullpath;
    off_t size;
} __attribute__((packed, aligned(4)));

struct dir_attrs {
    uint32_t length;
    fsobj_type_t type;
    uint32_t entries;
} __attribute__((packed, aligned(4)));

static void attributes(void)
{
    char exe[4096], real[4096];
    uint32_t exelen = sizeof exe;
    _NSGetExecutablePath(exe, &exelen);
    realpath(exe, real);
    struct stat st;
    stat(exe, &st);

    struct attrlist al = {0};
    al.bitmapcount = ATTR_BIT_MAP_COUNT;
    al.commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_FULLPATH;
    al.fileattr = ATTR_FILE_TOTALSIZE;
    char buf[8192];
    int rc = getattrlist(exe, &al, buf, sizeof buf, 0);
    struct file_attrs *f = (struct file_attrs *)buf;
    const char *name = (const char *)&f->name + f->name.attr_dataoffset;
    const char *full = (const char *)&f->fullpath + f->fullpath.attr_dataoffset;
    const char *base = strrchr(exe, '/') ? strrchr(exe, '/') + 1 : exe;
    printf("getattrlist: %s\n", rc == 0 ? "ok" : "failed");
    printf("returned attributes are the ones asked: %s\n",
           yes(f->returned.commonattr == al.commonattr && f->returned.fileattr == ATTR_FILE_TOTALSIZE));
    printf("name matches: %s, length counts the NUL: %s\n", yes(!strcmp(name, base)),
           yes(f->name.attr_length == strlen(base) + 1));
    printf("type is VREG: %s\n", yes(f->type == VREG));
    printf("modification time matches stat: %s\n", yes(f->modified.tv_sec == st.st_mtimespec.tv_sec &&
                                                       f->modified.tv_nsec == st.st_mtimespec.tv_nsec));
    printf("full path is the real path: %s\n", yes(!strcmp(full, real)));
    printf("total size matches stat: %s\n", yes(f->size == st.st_size));
    printf("length covers the names: %s\n", yes(f->length >= sizeof *f + strlen(base) + 1 + strlen(real) + 1 &&
                                                 f->length <= sizeof buf));

    uint32_t only_length;
    rc = getattrlist(exe, &al, &only_length, sizeof only_length, 0);
    printf("a 4-byte buffer: %s, length of what fits: %u\n", rc == 0 ? "ok" : "failed", only_length);
    rc = getattrlist(exe, &al, &only_length, sizeof only_length, FSOPT_REPORT_FULLSIZE);
    printf("with FSOPT_REPORT_FULLSIZE, the full length: %s\n", yes(rc == 0 && only_length == f->length));

    /* the program's folder */
    char dir[4096];
    snprintf(dir, sizeof dir, "%s", real);
    *strrchr(dir, '/') = 0;
    struct attrlist dl = {0};
    dl.bitmapcount = ATTR_BIT_MAP_COUNT;
    dl.commonattr = ATTR_CMN_OBJTYPE;
    dl.dirattr = ATTR_DIR_ENTRYCOUNT;
    struct dir_attrs d;
    unsigned entries = 0;
    DIR *dp = opendir(dir);
    for (struct dirent *e; dp && (e = readdir(dp));)
        if (strcmp(e->d_name, ".") && strcmp(e->d_name, ".."))
            entries++;
    if (dp)
        closedir(dp);
    rc = getattrlist(dir, &dl, &d, sizeof d, 0);
    printf("folder: %s, type is VDIR: %s, entry count matches readdir: %s\n", rc == 0 ? "ok" : "failed",
           yes(d.type == VDIR), yes(d.entries == entries));

    rc = getattrlist("/no/such/file", &dl, &d, sizeof d, 0);
    printf("a missing file: %s\n", err_name(rc ? errno : 0));
}

int main(int argc, char **argv)
{
    names();
    rules();
    process(argv[0], argc);
    mach();
    attributes();
    return 0;
}
