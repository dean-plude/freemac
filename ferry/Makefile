# SPDX-License-Identifier: GPL-3.0-or-later
CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -Wno-format-truncation -fno-strict-aliasing
LDLIBS = -Wl,--no-as-needed -lm -ldl -lpthread
PREFIX ?= /usr
DESTDIR ?=

SRC = src/main.c src/loader.c src/lookup.c src/errno.c src/stdio.c src/posix.c src/passthrough.c \
      src/objc/runtime.c src/objc/nsobject.c src/objc/blocks.c src/objc/symbols.c
OBJ = $(SRC:.c=.o) src/objc/msgsend.o
TBD = sdk/lib/libSystem.tbd sdk/lib/libobjc.tbd

# Ferry's own Foundation, built as a Mac library with ferry-cc (needs clang
# and lld, as the tests do). CoreFoundation is served from the same file.
FOUNDATION_SRC = $(wildcard foundation/*.m)
FOUNDATION_OBJ = $(FOUNDATION_SRC:foundation/%.m=foundation/build/%.o)
FOUNDATION = frameworks/Foundation.framework/Foundation
FOUNDATION_HEADERS = foundation/FInternal.h sdk/include/Foundation/Foundation.h \
                     sdk/include/CoreFoundation/CoreFoundation.h
OBJCFLAGS = -O2 -g -Wall -Wno-unused-parameter

all: ferry $(TBD) $(FOUNDATION)

ferry: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $(OBJ) $(LDLIBS)

src/%.o: src/%.c src/ferry.h src/macho.h src/objc/objc-private.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/objc/msgsend.o: src/objc/msgsend.S
	$(CC) -c -o $@ $<

sdk/lib/libSystem.tbd: ferry sdk/gen-tbd.sh
	mkdir -p sdk/lib
	sdk/gen-tbd.sh ./ferry libSystem > $@

sdk/lib/libobjc.tbd: ferry sdk/gen-tbd.sh
	mkdir -p sdk/lib
	sdk/gen-tbd.sh ./ferry libobjc > $@

foundation/build/%.o: foundation/%.m $(FOUNDATION_HEADERS) sdk/ferry-cc
	@mkdir -p foundation/build
	sdk/ferry-cc $(OBJCFLAGS) -c -o $@ $<

$(FOUNDATION): $(FOUNDATION_OBJ) $(TBD)
	@mkdir -p frameworks/Foundation.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation \
	    -o $@ $(FOUNDATION_OBJ) -lobjc
	@mkdir -p frameworks/CoreFoundation.framework
	sdk/gen-cf-tbd.sh $@ > frameworks/CoreFoundation.framework/CoreFoundation.tbd

check: all
	./tests/run.sh

install: ferry $(TBD) $(FOUNDATION)
	install -Dm755 ferry $(DESTDIR)$(PREFIX)/bin/ferry
	install -Dm755 sdk/ferry-cc $(DESTDIR)$(PREFIX)/bin/ferry-cc
	install -d $(DESTDIR)$(PREFIX)/share/ferry/sdk
	cp -r sdk/include sdk/lib $(DESTDIR)$(PREFIX)/share/ferry/sdk/
	install -Dm755 $(FOUNDATION) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/Foundation.framework/Foundation
	install -Dm644 frameworks/CoreFoundation.framework/CoreFoundation.tbd \
	    $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/CoreFoundation.framework/CoreFoundation.tbd
	install -Dm644 binfmt/ferry.conf $(DESTDIR)$(PREFIX)/lib/binfmt.d/ferry.conf

clean:
	rm -f ferry $(OBJ) $(TBD)
	rm -rf tests/build foundation/build frameworks

.PHONY: all check install clean
