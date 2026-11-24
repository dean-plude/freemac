# SPDX-License-Identifier: GPL-3.0-or-later
CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -Wno-format-truncation -fno-strict-aliasing
LDLIBS = -Wl,--no-as-needed -lm -ldl -lpthread
PREFIX ?= /usr
DESTDIR ?=

SRC = src/main.c src/loader.c src/lookup.c src/errno.c src/stdio.c src/posix.c src/passthrough.c src/host.c \
      src/objc/runtime.c src/objc/nsobject.c src/objc/blocks.c src/objc/dispatch.c src/objc/exception.c \
      src/objc/symbols.c
OBJ = $(SRC:.c=.o) src/objc/msgsend.o src/objc/unwind.o
TBD = sdk/lib/libSystem.tbd sdk/lib/libobjc.tbd
# Link stubs for the Mac libraries served by this system's copy (src/host.c).
TWIN_TBD = sdk/lib/libz.tbd sdk/lib/libbz2.tbd sdk/lib/liblzma.tbd sdk/lib/libxml2.tbd sdk/lib/libsqlite3.tbd \
           sdk/lib/libicucore.tbd

# Ferry's own Foundation, built as a Mac library with ferry-cc (needs clang
# and lld, as the tests do). CoreFoundation is served from the same file.
FOUNDATION_SRC = $(wildcard foundation/*.m)
FOUNDATION_OBJ = $(FOUNDATION_SRC:foundation/%.m=foundation/build/%.o)
FOUNDATION = frameworks/Foundation.framework/Foundation
FOUNDATION_HEADERS = foundation/FInternal.h sdk/include/Foundation/Foundation.h \
                     sdk/include/CoreFoundation/CoreFoundation.h sdk/include/SystemConfiguration/SystemConfiguration.h \
                     $(wildcard sdk/include/Foundation/NS*.h) \
                     foundation/FCurl.h
OBJCFLAGS = -O2 -g -Wall -Wno-unused-parameter

# Core Graphics and Core Text (M3), one Mac library that draws with this
# system's Cairo and Pango. CoreText, ApplicationServices and ImageIO are served from
# it, as CoreFoundation is from Foundation.
GRAPHICS_SRC = $(wildcard graphics/*.m)
GRAPHICS_OBJ = $(GRAPHICS_SRC:graphics/%.m=graphics/build/%.o)
GRAPHICS = frameworks/CoreGraphics.framework/CoreGraphics
GRAPHICS_HEADERS = graphics/GInternal.h graphics/host.h sdk/include/CoreGraphics/CoreGraphics.h \
                   sdk/include/CoreText/CoreText.h sdk/include/ImageIO/ImageIO.h $(FOUNDATION_HEADERS)
HOST_TBD = graphics/build/libFerryHost.tbd

# Core Animation (QuartzCore): layers drawn with the library above and
# animated on the main run loop.
QUARTZCORE_SRC = $(wildcard quartzcore/*.m)
QUARTZCORE_OBJ = $(QUARTZCORE_SRC:quartzcore/%.m=quartzcore/build/%.o)
QUARTZCORE = frameworks/QuartzCore.framework/QuartzCore
QUARTZCORE_HEADERS = quartzcore/QInternal.h $(wildcard sdk/include/QuartzCore/*.h) $(GRAPHICS_HEADERS)

# AppKit (M4): windows through this system's GTK, drawn with the library
# above. Cocoa is served from it.
APPKIT_SRC = $(wildcard appkit/*.m)
APPKIT_OBJ = $(APPKIT_SRC:appkit/%.m=appkit/build/%.o)
APPKIT = frameworks/AppKit.framework/AppKit
APPKIT_HEADERS = appkit/AInternal.h appkit/gtk.h sdk/include/AppKit/AppKit.h $(QUARTZCORE_HEADERS)

# Ferry's own Installer (installer/), a Mac app built against the frameworks above.
INSTALLER_SRC = installer/Installer.m installer/IPackage.m
INSTALLER_APP = installer/Installer.app
INSTALLER = $(INSTALLER_APP)/Contents/MacOS/Installer

all: ferry $(TBD) $(TWIN_TBD) $(FOUNDATION) $(GRAPHICS) $(QUARTZCORE) $(APPKIT) $(INSTALLER)

ferry: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $(OBJ) $(LDLIBS)

src/%.o: src/%.c src/ferry.h src/macho.h src/objc/objc-private.h
	$(CC) $(CFLAGS) -c -o $@ $<

# The Cairo, Pango, HarfBuzz, GTK, GdkPixbuf and Poppler calls Ferry's frameworks may make:
# exactly the ones graphics/host.h and appkit/gtk.h declare.
src/host_names.h: graphics/host.h appkit/gtk.h
	cat $^ | grep -oE '\b(cairo|pango|g|hb|gtk|gdk|poppler)_[a-z0-9_]+\(' | tr -d '(' | sort -u | sed 's/.*/    "&",/' > $@

src/host.o: src/host_names.h

src/objc/%.o: src/objc/%.S
	$(CC) -c -o $@ $<

sdk/lib/libSystem.tbd: ferry sdk/gen-tbd.sh
	mkdir -p sdk/lib
	sdk/gen-tbd.sh ./ferry libSystem > $@

sdk/lib/libz.tbd: sdk/gen-twin-tbd.sh
	@mkdir -p sdk/lib
	sdk/gen-twin-tbd.sh /usr/lib/libz.1.dylib libz.so.1 > $@
sdk/lib/libbz2.tbd: sdk/gen-twin-tbd.sh
	@mkdir -p sdk/lib
	sdk/gen-twin-tbd.sh /usr/lib/libbz2.1.0.dylib libbz2.so.1.0 > $@
sdk/lib/liblzma.tbd: sdk/gen-twin-tbd.sh
	@mkdir -p sdk/lib
	sdk/gen-twin-tbd.sh /usr/lib/liblzma.5.dylib liblzma.so.5 > $@
sdk/lib/libxml2.tbd: sdk/gen-twin-tbd.sh
	@mkdir -p sdk/lib
	sdk/gen-twin-tbd.sh /usr/lib/libxml2.2.dylib libxml2.so.2 > $@
sdk/lib/libsqlite3.tbd: sdk/gen-twin-tbd.sh
	@mkdir -p sdk/lib
	sdk/gen-twin-tbd.sh /usr/lib/libsqlite3.dylib libsqlite3.so.0 > $@
sdk/lib/libicucore.tbd: sdk/gen-twin-tbd.sh
	@mkdir -p sdk/lib
	sdk/gen-twin-tbd.sh /usr/lib/libicucore.A.dylib icu > $@

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
	@mkdir -p frameworks/SystemConfiguration.framework
	sdk/gen-alias-tbd.sh SystemConfiguration $@ > frameworks/SystemConfiguration.framework/SystemConfiguration.tbd

$(HOST_TBD): ferry sdk/gen-tbd.sh
	@mkdir -p graphics/build
	sdk/gen-tbd.sh ./ferry libFerryHost > $@

graphics/build/%.o: graphics/%.m $(GRAPHICS_HEADERS) sdk/ferry-cc
	@mkdir -p graphics/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

$(GRAPHICS): $(GRAPHICS_OBJ) $(FOUNDATION) $(HOST_TBD)
	@mkdir -p frameworks/CoreGraphics.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics \
	    -o $@ $(GRAPHICS_OBJ) -framework Foundation $(HOST_TBD)
	@mkdir -p frameworks/CoreText.framework frameworks/ApplicationServices.framework frameworks/ImageIO.framework
	sdk/gen-alias-tbd.sh CoreText $@ > frameworks/CoreText.framework/CoreText.tbd
	sdk/gen-alias-tbd.sh ImageIO $@ > frameworks/ImageIO.framework/ImageIO.tbd
	sdk/gen-alias-tbd.sh ApplicationServices $@ > frameworks/ApplicationServices.framework/ApplicationServices.tbd

quartzcore/build/%.o: quartzcore/%.m $(QUARTZCORE_HEADERS) sdk/ferry-cc
	@mkdir -p quartzcore/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

$(QUARTZCORE): $(QUARTZCORE_OBJ) $(GRAPHICS)
	@mkdir -p frameworks/QuartzCore.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore \
	    -o $@ $(QUARTZCORE_OBJ) -framework Foundation -framework CoreGraphics

appkit/build/%.o: appkit/%.m $(APPKIT_HEADERS) sdk/ferry-cc
	@mkdir -p appkit/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

$(APPKIT): $(APPKIT_OBJ) $(GRAPHICS) $(QUARTZCORE) $(HOST_TBD)
	@mkdir -p frameworks/AppKit.framework frameworks/Cocoa.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
	    -o $@ $(APPKIT_OBJ) -framework Foundation -framework CoreGraphics -framework QuartzCore $(HOST_TBD)
	sdk/gen-alias-tbd.sh Cocoa $@ $(FOUNDATION) $(GRAPHICS) > frameworks/Cocoa.framework/Cocoa.tbd
	@mkdir -p frameworks/Carbon.framework
	sdk/gen-alias-tbd.sh Carbon $@ > frameworks/Carbon.framework/Carbon.tbd

$(INSTALLER): $(INSTALLER_SRC) installer/IPackage.h installer/Info.plist $(APPKIT) $(TWIN_TBD)
	@mkdir -p $(INSTALLER_APP)/Contents/MacOS
	cp installer/Info.plist $(INSTALLER_APP)/Contents/Info.plist
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -o $@ $(INSTALLER_SRC) -framework Cocoa -lz -llzma

check: all
	./tests/run.sh

install: ferry $(TBD) $(TWIN_TBD) $(FOUNDATION) $(GRAPHICS) $(QUARTZCORE) $(APPKIT) $(INSTALLER)
	install -Dm755 $(INSTALLER) $(DESTDIR)$(PREFIX)/lib/ferry/Installer.app/Contents/MacOS/Installer
	install -Dm644 $(INSTALLER_APP)/Contents/Info.plist $(DESTDIR)$(PREFIX)/lib/ferry/Installer.app/Contents/Info.plist
	install -Dm644 packaging/ferry-installer.desktop $(DESTDIR)$(PREFIX)/share/applications/ferry-installer.desktop
	install -Dm755 ferry $(DESTDIR)$(PREFIX)/bin/ferry
	install -Dm755 sdk/ferry-cc $(DESTDIR)$(PREFIX)/bin/ferry-cc
	install -d $(DESTDIR)$(PREFIX)/share/ferry/sdk
	cp -r sdk/include sdk/lib $(DESTDIR)$(PREFIX)/share/ferry/sdk/
	install -Dm755 $(FOUNDATION) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/Foundation.framework/Foundation
	install -Dm644 frameworks/CoreFoundation.framework/CoreFoundation.tbd \
	    $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/CoreFoundation.framework/CoreFoundation.tbd
	install -Dm755 $(GRAPHICS) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/CoreGraphics.framework/CoreGraphics
	install -Dm755 $(QUARTZCORE) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/QuartzCore.framework/QuartzCore
	install -Dm755 $(APPKIT) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/AppKit.framework/AppKit
	for f in CoreText ApplicationServices ImageIO Cocoa SystemConfiguration Carbon; do \
	    install -Dm644 frameworks/$$f.framework/$$f.tbd $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/$$f.framework/$$f.tbd; \
	done
	install -Dm644 binfmt/ferry.conf $(DESTDIR)$(PREFIX)/lib/binfmt.d/ferry.conf

clean:
	rm -f ferry $(OBJ) $(TBD) src/host_names.h
	rm -rf tests/build foundation/build graphics/build quartzcore/build appkit/build frameworks installer/Installer.app

.PHONY: all check install clean
