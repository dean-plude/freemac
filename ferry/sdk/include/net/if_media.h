/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 *
 * A network interface's media, as a Mac's net/if_media.h names it (for
 * Qt's QNetworkInterface). Ferry answers SIOCGIFMEDIA with ENOTTY, so a
 * program falls back to the interface's type from getifaddrs. */
#ifndef _NET_IF_MEDIA_H_
#define _NET_IF_MEDIA_H_
#include <net/if.h>

struct ifmediareq {
    char ifm_name[IFNAMSIZ];
    int ifm_current;
    int ifm_mask;
    int ifm_status;
    int ifm_active;
    int ifm_count;
    int *ifm_ulist;
};

#define SIOCGIFMEDIA 0xc0306938ul /* _IOWR('i', 56, struct ifmediareq) */
#define SIOCSIFMEDIA 0xc0206937ul /* _IOWR('i', 55, struct ifreq) */

#define IFM_NMASK 0x000000e0
#define IFM_TMASK 0x0000001f
#define IFM_TYPE(x) ((x) & IFM_NMASK)
#define IFM_SUBTYPE(x) ((x) & IFM_TMASK)
#define IFM_ETHER 0x00000020
#define IFM_TOKEN 0x00000040
#define IFM_FDDI 0x00000060
#define IFM_IEEE80211 0x00000080
#define IFM_AVALID 0x00000001
#define IFM_ACTIVE 0x00000002
#define IFM_AUTO 0
#define IFM_FDX 0x00100000
#define IFM_HDX 0x00200000
#endif
