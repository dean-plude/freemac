/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* Darwin.POSIX, for "@import Darwin.POSIX;" (freemac 1.225, Ferry 0.49.0):
 * the POSIX calls beside the C library's. */
#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <libgen.h>
#include <netdb.h>
#include <poll.h>
#include <pthread.h>
#include <pwd.h>
#include <sched.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/mman.h>
#include <sys/wait.h>
/* for Swift's Darwin overlay (freemac 1.227) */
#include <MacTypes.h>
#include <semaphore.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <sys/sysctl.h>
#include <sys/uio.h>
#include <sys/utsname.h>
