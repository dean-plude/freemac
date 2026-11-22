# SPDX-License-Identifier: GPL-3.0-or-later
"""The Guest User, as on a Mac: an account anyone can log in to without a
password, whose home folder is emptied each time they log in and log out, so
nothing a guest does is kept.

Dials > Users turns it on and off through freemac-users-helper, which makes
or removes the account `guest` and the mark /etc/freemac/guest-user. Only an
account with that name *and* the mark is treated as the Guest User, so an
ordinary account someone happened to call "guest" is never emptied.
freemac-session does the emptying. Original freemac code.
"""
import os
import pwd

NAME = "guest"
FULL_NAME = "Guest User"
MARK = "/etc/freemac/guest-user"
HOME = "/home/guest"


def is_guest(name):
    return name == NAME and os.path.exists(MARK)


def enabled():
    if not os.path.exists(MARK):
        return False
    try:
        pwd.getpwnam(NAME)
    except KeyError:
        return False
    return True
