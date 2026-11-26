/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * copyfile and fcopyfile (freemac 1.232, Ferry 0.56.0), with the names and
 * flags of the copyfile(3) manual page. Ferry copies a file's data, its
 * permissions, owner and times (COPYFILE_STAT) and its extended
 * attributes (COPYFILE_XATTR); access control lists aren't kept. Qt's
 * QFile::copy uses fcopyfile. */
#ifndef _FERRY_COPYFILE_H_
#define _FERRY_COPYFILE_H_
#include <_ferry.h>
__FERRY_BEGIN
typedef struct _copyfile_state *copyfile_state_t;
typedef uint32_t copyfile_flags_t;
#define COPYFILE_ACL (1 << 0)
#define COPYFILE_STAT (1 << 1)
#define COPYFILE_XATTR (1 << 2)
#define COPYFILE_DATA (1 << 3)
#define COPYFILE_SECURITY (COPYFILE_STAT | COPYFILE_ACL)
#define COPYFILE_METADATA (COPYFILE_SECURITY | COPYFILE_XATTR)
#define COPYFILE_ALL (COPYFILE_METADATA | COPYFILE_DATA)
#define COPYFILE_RECURSIVE (1 << 15)
#define COPYFILE_CHECK (1 << 16)
#define COPYFILE_EXCL (1 << 17)
#define COPYFILE_NOFOLLOW_SRC (1 << 18)
#define COPYFILE_NOFOLLOW_DST (1 << 19)
#define COPYFILE_MOVE (1 << 20)
#define COPYFILE_UNLINK (1 << 21)
#define COPYFILE_NOFOLLOW (COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST)
#define COPYFILE_CLONE (1 << 24)
#define COPYFILE_CLONE_FORCE (1 << 25)
#define COPYFILE_DATA_SPARSE (1 << 27)
int copyfile(const char *from, const char *to, copyfile_state_t state, copyfile_flags_t flags);
int fcopyfile(int from_fd, int to_fd, copyfile_state_t state, copyfile_flags_t flags);
copyfile_state_t copyfile_state_alloc(void);
int copyfile_state_free(copyfile_state_t state);
__FERRY_END
#endif
