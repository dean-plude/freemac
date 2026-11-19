# SPDX-License-Identifier: GPL-3.0-or-later
CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -fno-strict-aliasing
LDLIBS = -Wl,--no-as-needed -lm -ldl
PREFIX ?= /usr
DESTDIR ?=

SRC = src/main.c src/loader.c src/lookup.c src/errno.c src/stdio.c src/posix.c src/passthrough.c
OBJ = $(SRC:.c=.o)

all: ferry sdk/lib/libSystem.tbd

ferry: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $(OBJ) $(LDLIBS)

src/%.o: src/%.c src/ferry.h src/macho.h
	$(CC) $(CFLAGS) -c -o $@ $<

sdk/lib/libSystem.tbd: ferry sdk/gen-tbd.sh
	mkdir -p sdk/lib
	sdk/gen-tbd.sh ./ferry > $@

check: all
	./tests/run.sh

install: ferry sdk/lib/libSystem.tbd
	install -Dm755 ferry $(DESTDIR)$(PREFIX)/bin/ferry
	install -Dm755 sdk/ferry-cc $(DESTDIR)$(PREFIX)/bin/ferry-cc
	install -d $(DESTDIR)$(PREFIX)/share/ferry/sdk
	cp -r sdk/include sdk/lib $(DESTDIR)$(PREFIX)/share/ferry/sdk/
	install -Dm644 binfmt/ferry.conf $(DESTDIR)$(PREFIX)/lib/binfmt.d/ferry.conf

clean:
	rm -f ferry $(OBJ) sdk/lib/libSystem.tbd
	rm -rf tests/build

.PHONY: all check install clean
