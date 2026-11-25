/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A terminal's settings for Mac programs (freemac 1.232, Ferry 0.56.0). A
 * Mac's struct termios has long flag words with BSD's bit numbers, 20
 * control characters in BSD's order and speeds as plain numbers; this
 * system's has int words, other bits, 32 characters and speed codes. The
 * calls that touch a terminal translate both ways; the ones that only change
 * the structure work on the Mac's own numbers.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include "ferry.h"

#define MAC_NCCS 20
struct mac_termios {
    unsigned long c_iflag, c_oflag, c_cflag, c_lflag;
    unsigned char c_cc[MAC_NCCS];
    unsigned long c_ispeed, c_ospeed;
};

struct bit {
    unsigned long mac;
    tcflag_t lnx;
};

static const struct bit iflags[] = {
    {0x1, IGNBRK}, {0x2, BRKINT}, {0x4, IGNPAR}, {0x8, PARMRK},   {0x10, INPCK},    {0x20, ISTRIP},  {0x40, INLCR},
    {0x80, IGNCR}, {0x100, ICRNL}, {0x200, IXON}, {0x400, IXOFF}, {0x800, IXANY}, {0x2000, IMAXBEL}, {0x4000, IUTF8},
};
static const struct bit oflags[] = {
    {0x1, OPOST}, {0x2, ONLCR}, {0x4, XTABS}, {0x10, OCRNL}, {0x20, ONOCR}, {0x40, ONLRET},
};
static const struct bit cflags[] = {
    {0x400, CSTOPB}, {0x800, CREAD}, {0x1000, PARENB}, {0x2000, PARODD}, {0x4000, HUPCL}, {0x8000, CLOCAL},
};
static const struct bit lflags[] = {
    {0x1, ECHOKE},  {0x2, ECHOE},     {0x4, ECHOK},    {0x8, ECHO},        {0x10, ECHONL},       {0x20, ECHOPRT},
    {0x40, ECHOCTL}, {0x80, ISIG},    {0x100, ICANON}, {0x400, IEXTEN},    {0x800, EXTPROC},     {0x400000, TOSTOP},
    {0x800000, FLUSHO}, {0x20000000, PENDIN}, {0x80000000ul, NOFLSH},
};
#define N(a) (sizeof a / sizeof a[0])

/* the control characters: a Mac's place, this system's */
static const struct {
    int mac, lnx;
} ccs[] = {
    {0, VEOF},     {1, VEOL},   {2, VEOL2},  {3, VERASE}, {4, VWERASE}, {5, VKILL},     {6, VREPRINT},
    {8, VINTR},    {9, VQUIT},  {10, VSUSP}, {12, VSTART}, {13, VSTOP},  {14, VLNEXT}, {15, VDISCARD},
    {16, VMIN},    {17, VTIME},
};

static const struct {
    unsigned long baud;
    speed_t code;
} speeds[] = {
    {0, B0},           {50, B50},         {75, B75},         {110, B110},       {134, B134},       {150, B150},
    {200, B200},       {300, B300},       {600, B600},       {1200, B1200},     {1800, B1800},     {2400, B2400},
    {4800, B4800},     {9600, B9600},     {19200, B19200},   {38400, B38400},   {57600, B57600},   {115200, B115200},
    {230400, B230400}, {460800, B460800}, {500000, B500000}, {576000, B576000}, {921600, B921600}, {1000000, B1000000},
};

static tcflag_t to_lnx(unsigned long mac, const struct bit *b, size_t n)
{
    tcflag_t out = 0;
    for (size_t i = 0; i < n; i++)
        if ((mac & b[i].mac) == b[i].mac)
            out |= b[i].lnx;
    return out;
}

static unsigned long to_mac(tcflag_t lnx, const struct bit *b, size_t n)
{
    unsigned long out = 0;
    for (size_t i = 0; i < n; i++)
        if ((lnx & b[i].lnx) == b[i].lnx)
            out |= b[i].mac;
    return out;
}

static unsigned long baud_of(speed_t code)
{
    for (size_t i = 0; i < N(speeds); i++)
        if (speeds[i].code == code)
            return speeds[i].baud;
    return 0;
}

static int code_of(unsigned long baud, speed_t *code)
{
    for (size_t i = 0; i < N(speeds); i++)
        if (speeds[i].baud == baud) {
            *code = speeds[i].code;
            return 0;
        }
    return -1;
}

static void termios_to_mac(const struct termios *l, struct mac_termios *m)
{
    memset(m, 0, sizeof *m);
    m->c_iflag = to_mac(l->c_iflag, iflags, N(iflags));
    m->c_oflag = to_mac(l->c_oflag, oflags, N(oflags));
    m->c_cflag = to_mac(l->c_cflag, cflags, N(cflags));
    /* the character size: CS5 to CS8 are 0 to 3 in both, at bits 8 and 9 on a Mac */
    m->c_cflag |= (unsigned long)((l->c_cflag & CSIZE) / CS6) << 8;
    if (l->c_cflag & CRTSCTS)
        m->c_cflag |= 0x30000;
    m->c_lflag = to_mac(l->c_lflag, lflags, N(lflags));
    memset(m->c_cc, 0xff, sizeof m->c_cc); /* VDSUSP and VSTATUS: none here */
    for (size_t i = 0; i < N(ccs); i++)
        m->c_cc[ccs[i].mac] = l->c_cc[ccs[i].lnx];
    m->c_ispeed = baud_of(cfgetispeed(l));
    m->c_ospeed = baud_of(cfgetospeed(l));
}

static int termios_to_lnx(const struct mac_termios *m, struct termios *l)
{
    l->c_iflag = to_lnx(m->c_iflag, iflags, N(iflags));
    l->c_oflag = to_lnx(m->c_oflag, oflags, N(oflags));
    l->c_cflag = to_lnx(m->c_cflag, cflags, N(cflags));
    l->c_cflag |= (tcflag_t)((m->c_cflag >> 8) & 3) * CS6;
    if (m->c_cflag & 0x30000)
        l->c_cflag |= CRTSCTS;
    l->c_lflag = to_lnx(m->c_lflag, lflags, N(lflags));
    for (size_t i = 0; i < N(ccs); i++)
        l->c_cc[ccs[i].lnx] = m->c_cc[ccs[i].mac] == 0xff ? _POSIX_VDISABLE : m->c_cc[ccs[i].mac];
    speed_t in, out;
    if (code_of(m->c_ispeed, &in) || code_of(m->c_ospeed, &out)) {
        errno = EINVAL;
        return -1;
    }
    cfsetispeed(l, in);
    cfsetospeed(l, out);
    return 0;
}

static int mac_tcgetattr(int fd, struct mac_termios *m)
{
    struct termios l;
    if (tcgetattr(fd, &l) < 0)
        return -1;
    termios_to_mac(&l, m);
    return 0;
}

/* TCSASOFT (0x10) keeps the terminal's own hardware settings: its speeds,
 * size and parity stay as they are. */
static int mac_tcsetattr(int fd, int when, const struct mac_termios *m)
{
    int soft = when & 0x10;
    when &= ~0x10;
    if (when < 0 || when > 2) {
        errno = EINVAL;
        return -1;
    }
    struct termios l, now;
    if (tcgetattr(fd, &now) < 0)
        return -1;
    l = now;
    if (termios_to_lnx(m, &l) < 0)
        return -1;
    if (soft || (m->c_cflag & 0x1)) { /* CIGNORE too: leave the control word as it is */
        l.c_cflag = now.c_cflag;
        cfsetispeed(&l, cfgetispeed(&now));
        cfsetospeed(&l, cfgetospeed(&now));
    }
    static const int whens[] = {TCSANOW, TCSADRAIN, TCSAFLUSH};
    return tcsetattr(fd, whens[when], &l);
}

static unsigned long mac_cfgetispeed(const struct mac_termios *m) { return m->c_ispeed; }
static unsigned long mac_cfgetospeed(const struct mac_termios *m) { return m->c_ospeed; }
static int mac_cfsetispeed(struct mac_termios *m, unsigned long s) { m->c_ispeed = s; return 0; }
static int mac_cfsetospeed(struct mac_termios *m, unsigned long s) { m->c_ospeed = s; return 0; }
static int mac_cfsetspeed(struct mac_termios *m, unsigned long s) { m->c_ispeed = m->c_ospeed = s; return 0; }

/* As BSD's cfmakeraw: no echo, no line editing, no signals, 8 bits. */
static void mac_cfmakeraw(struct mac_termios *m)
{
    m->c_iflag &= ~(0x2000ul | 0x400 | 0x10 | 0x2 | 0x8 | 0x20 | 0x40 | 0x80 | 0x100 | 0x200 | 0x4);
    m->c_iflag |= 0x1;
    m->c_oflag &= ~0x1ul;
    m->c_cflag &= ~(0x300ul | 0x1000);
    m->c_cflag |= 0x300 | 0x800;
    m->c_lflag &= ~(0x8ul | 0x2 | 0x4 | 0x10 | 0x100 | 0x80 | 0x400 | 0x80000000ul | 0x400000 | 0x20000000);
    m->c_cc[16] = 1; /* VMIN */
    m->c_cc[17] = 0; /* VTIME */
}

static int mac_tcflush(int fd, int which)
{
    static const int q[] = {-1, TCIFLUSH, TCOFLUSH, TCIOFLUSH};
    if (which < 1 || which > 3) {
        errno = EINVAL;
        return -1;
    }
    return tcflush(fd, q[which]);
}

static int mac_tcflow(int fd, int action)
{
    static const int a[] = {-1, TCOOFF, TCOON, TCIOFF, TCION};
    if (action < 1 || action > 4) {
        errno = EINVAL;
        return -1;
    }
    return tcflow(fd, a[action]);
}

const struct ferry_symbol ferry_termios_symbols[] = {
    {"tcgetattr", mac_tcgetattr},
    {"tcsetattr", mac_tcsetattr},
    {"cfgetispeed", mac_cfgetispeed},
    {"cfgetospeed", mac_cfgetospeed},
    {"cfsetispeed", mac_cfsetispeed},
    {"cfsetospeed", mac_cfsetospeed},
    {"cfsetspeed", mac_cfsetspeed},
    {"cfmakeraw", mac_cfmakeraw},
    {"tcflush", mac_tcflush},
    {"tcflow", mac_tcflow},
    {"tcdrain", tcdrain},
    {"tcsendbreak", tcsendbreak},
    {"tcgetsid", tcgetsid},
    {"tcgetpgrp", tcgetpgrp},
    {"tcsetpgrp", tcsetpgrp},
    {NULL, NULL},
};
