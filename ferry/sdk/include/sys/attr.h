/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * A file's attributes in one call, from the getattrlist(2) man page. Only
 * the attributes Ferry serves are named here. */
#ifndef _SYS_ATTR_H_
#define _SYS_ATTR_H_
#include <_ferry.h>
#include <time.h>
__FERRY_BEGIN
typedef uint32_t attrgroup_t;
typedef uint32_t fsobj_type_t;
typedef struct fsobj_id { uint32_t fid_objno, fid_generation; } fsobj_id_t;
typedef struct fsid { int32_t val[2]; } fsid_t;
typedef struct attrreference { int32_t attr_dataoffset; uint32_t attr_length; } attrreference_t;
typedef struct attribute_set { attrgroup_t commonattr, volattr, dirattr, fileattr, forkattr; } attribute_set_t;
struct attrlist {
    unsigned short bitmapcount;
    uint16_t reserved;
    attrgroup_t commonattr, volattr, dirattr, fileattr, forkattr;
};
#define ATTR_BIT_MAP_COUNT 5
#define FSOPT_NOFOLLOW 0x00000001
#define FSOPT_REPORT_FULLSIZE 0x00000004
#define FSOPT_PACK_INVAL_ATTRS 0x00000008

#define ATTR_CMN_NAME 0x00000001
#define ATTR_CMN_DEVID 0x00000002
#define ATTR_CMN_FSID 0x00000004
#define ATTR_CMN_OBJTYPE 0x00000008
#define ATTR_CMN_OBJID 0x00000020
#define ATTR_CMN_OBJPERMANENTID 0x00000040
#define ATTR_CMN_PAROBJID 0x00000080
#define ATTR_CMN_CRTIME 0x00000200
#define ATTR_CMN_MODTIME 0x00000400
#define ATTR_CMN_CHGTIME 0x00000800
#define ATTR_CMN_ACCTIME 0x00001000
#define ATTR_CMN_BKUPTIME 0x00002000
#define ATTR_CMN_FNDRINFO 0x00004000
#define ATTR_CMN_OWNERID 0x00008000
#define ATTR_CMN_GRPID 0x00010000
#define ATTR_CMN_ACCESSMASK 0x00020000
#define ATTR_CMN_FLAGS 0x00040000
#define ATTR_CMN_USERACCESS 0x00200000
#define ATTR_CMN_FILEID 0x02000000
#define ATTR_CMN_PARENTID 0x04000000
#define ATTR_CMN_FULLPATH 0x08000000
#define ATTR_CMN_RETURNED_ATTRS 0x80000000

#define ATTR_DIR_LINKCOUNT 0x00000001
#define ATTR_DIR_ENTRYCOUNT 0x00000002
#define ATTR_DIR_MOUNTSTATUS 0x00000004
#define DIR_MNTSTATUS_MNTPOINT 0x00000001

#define ATTR_FILE_LINKCOUNT 0x00000001
#define ATTR_FILE_TOTALSIZE 0x00000002
#define ATTR_FILE_ALLOCSIZE 0x00000004
#define ATTR_FILE_IOBLOCKSIZE 0x00000008
#define ATTR_FILE_DEVTYPE 0x00000020
#define ATTR_FILE_DATALENGTH 0x00000200
#define ATTR_FILE_DATAALLOCSIZE 0x00000400
#define ATTR_FILE_RSRCLENGTH 0x00001000
#define ATTR_FILE_RSRCALLOCSIZE 0x00002000

enum vtype { VNON, VREG, VDIR, VBLK, VCHR, VLNK, VSOCK, VFIFO, VBAD, VSTR, VCPLX };

int getattrlist(const char *path, void *attrList, void *attrBuf, size_t attrBufSize, unsigned int options);
int fgetattrlist(int fd, void *attrList, void *attrBuf, size_t attrBufSize, unsigned int options);
__FERRY_END
#endif
