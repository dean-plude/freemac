/* SPDX-License-Identifier: GPL-3.0-or-later
 * A terminal's settings with a Mac's struct termios and BSD's numbers, on
 * a pseudo-terminal (freemac 1.233, Ferry 0.57.0): what a new terminal
 * starts with, raw mode as cfmakeraw and FFmpeg's ffmpeg set it, speeds,
 * control characters, TCSASOFT, flushing and the errors. */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

static const char *yes(int b) { return b ? "yes" : "no"; }

static int pending(int fd)
{
    struct pollfd p = {fd, POLLIN, 0};
    return poll(&p, 1, 100) == 1;
}

int main(void)
{
    printf("sizeof(struct termios) %zu, NCCS %d\n", sizeof(struct termios), NCCS);
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0 || grantpt(master) != 0 || unlockpt(master) != 0) {
        printf("no pseudo-terminal: %s\n", strerror(errno));
        return 1;
    }
    const char *name = ptsname(master);
    printf("posix_openpt, grantpt, unlockpt: ok, ptsname under /dev/pts: %s\n",
           name && !strncmp(name, "/dev/pts/", 9) ? "yes" : "no");
    int tty = open(name, O_RDWR | O_NOCTTY);
    printf("isatty: %s\n", yes(isatty(tty)));

    struct termios t;
    printf("tcgetattr: %d\n", tcgetattr(tty, &t));
    printf("a new terminal: ICANON %s, ECHO %s, ISIG %s, ICRNL %s, OPOST %s, ONLCR %s, CS8 %s, CREAD %s\n",
           yes(t.c_lflag & ICANON), yes(t.c_lflag & ECHO), yes(t.c_lflag & ISIG), yes(t.c_iflag & ICRNL),
           yes(t.c_oflag & OPOST), yes(t.c_oflag & ONLCR), yes((t.c_cflag & CSIZE) == CS8), yes(t.c_cflag & CREAD));
    printf("  VINTR %d, VQUIT %d, VERASE %d, VKILL %d, VEOF %d, VSUSP %d, VSTART %d, VSTOP %d\n", t.c_cc[VINTR],
           t.c_cc[VQUIT], t.c_cc[VERASE], t.c_cc[VKILL], t.c_cc[VEOF], t.c_cc[VSUSP], t.c_cc[VSTART], t.c_cc[VSTOP]);

    /* canonical mode with echo: a line comes back to the other side with \r\n */
    if (write(master, "hi\n", 3) != 3)
        return 1;
    char buf[64];
    ssize_t n = read(tty, buf, sizeof buf);
    printf("canonical: read %zd bytes, \"hi\\n\": %s\n", n, yes(n == 3 && !memcmp(buf, "hi\n", 3)));
    n = read(master, buf, sizeof buf);
    printf("  echoed back: %s\n", yes(n == 4 && !memcmp(buf, "hi\r\n", 4)));

    /* raw mode, as cfmakeraw gives it */
    struct termios raw = t;
    cfmakeraw(&raw);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    printf("tcsetattr raw, TCSANOW: %d\n", tcsetattr(tty, TCSANOW, &raw));
    struct termios now;
    tcgetattr(tty, &now);
    printf("raw read back: ICANON %s, ECHO %s, ISIG %s, ICRNL %s, OPOST %s, CS8 %s, VMIN %d, VTIME %d\n",
           yes(now.c_lflag & ICANON), yes(now.c_lflag & ECHO), yes(now.c_lflag & ISIG), yes(now.c_iflag & ICRNL),
           yes(now.c_oflag & OPOST), yes((now.c_cflag & CSIZE) == CS8), now.c_cc[VMIN], now.c_cc[VTIME]);
    if (write(master, "q\r", 2) != 2)
        return 1;
    n = read(tty, buf, sizeof buf);
    printf("raw: read %zd bytes, 'q' then '\\r' unchanged: %s, nothing echoed: %s\n", n,
           yes(n == 2 && buf[0] == 'q' && buf[1] == '\r'), yes(!pending(master)));
    if (write(tty, "a\n", 2) != 2)
        return 1;
    n = read(master, buf, sizeof buf);
    printf("raw output: \"a\\n\" arrives as it is: %s\n", yes(n == 2 && buf[1] == '\n'));

    /* the speeds are baud rates, as on a Mac */
    struct termios s = now;
    printf("cfsetspeed(B115200): %d, cfsetspeed(12345): %d (EINVAL %s)\n", cfsetspeed(&s, B115200),
           cfsetspeed(&s, 12345), yes(errno == EINVAL));
    tcsetattr(tty, TCSADRAIN, &s);
    tcgetattr(tty, &now);
    printf("speeds read back: %lu in, %lu out\n", (unsigned long)cfgetispeed(&now), (unsigned long)cfgetospeed(&now));

    /* a control character (a pseudo-terminal keeps CS8 and no parity on
     * Linux, whatever c_cflag asks, so that isn't tried) */
    s.c_cc[VINTR] = 7;
    s.c_cc[VEOF] = 1;
    printf("tcsetattr TCSAFLUSH: %d\n", tcsetattr(tty, TCSAFLUSH, &s));
    tcgetattr(tty, &now);
    printf("VINTR set to 7: %d, VEOF set to 1: %d\n", now.c_cc[VINTR], now.c_cc[VEOF]);
    /* TCSASOFT leaves the hardware settings, the speeds among them, alone */
    struct termios soft = now;
    cfsetspeed(&soft, B9600);
    soft.c_lflag |= ECHO;
    printf("tcsetattr TCSANOW | TCSASOFT: %d\n", tcsetattr(tty, TCSANOW | TCSASOFT, &soft));
    tcgetattr(tty, &now);
    printf("  ECHO now %s, still %lu baud\n", yes(now.c_lflag & ECHO), (unsigned long)cfgetospeed(&now));

    tcsetattr(tty, TCSANOW, &t);
    tcgetattr(tty, &now);
    printf("back to the first settings: ICANON %s, VINTR %d, %lu baud\n", yes(now.c_lflag & ICANON), now.c_cc[VINTR],
           (unsigned long)cfgetospeed(&now));

    if (write(master, "unread", 6) != 6)
        return 1;
    printf("tcflush TCIFLUSH: %d, then nothing to read: %s\n", tcflush(tty, TCIFLUSH), yes(!pending(tty)));
    printf("tcflush 0: %d (EINVAL %s); tcdrain: %d; tcflow TCOON: %d\n", tcflush(tty, 0), yes(errno == EINVAL),
           tcdrain(tty), tcflow(tty, TCOON));
    printf("tcsetattr with action 7: %d (EINVAL %s)\n", tcsetattr(tty, 7, &t), yes(errno == EINVAL));
    int null = open("/dev/null", O_RDWR);
    printf("tcgetattr of /dev/null: %d (ENOTTY %s)\n", tcgetattr(null, &now), yes(errno == ENOTTY));
    close(null);
    close(tty);
    close(master);
    return 0;
}
