# SPDX-License-Identifier: GPL-3.0-or-later
CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -Wno-format-truncation -fno-strict-aliasing
LDLIBS = -Wl,--no-as-needed -lm -ldl -lpthread
PREFIX ?= /usr
DESTDIR ?=

SRC = src/main.c src/loader.c src/lookup.c src/errno.c src/stdio.c src/posix.c src/pthread.c src/passthrough.c src/host.c \
      src/commoncrypto.c src/sysversion.c src/servercerts.c src/sysctl.c src/attrlist.c src/dyld.c \
      src/socket.c src/kqueue.c src/libc_more.c \
      src/objc/runtime.c src/objc/nsobject.c src/objc/blocks.c src/objc/dispatch.c src/objc/exception.c \
      src/objc/symbols.c src/objc/oslog.c src/cxx.c src/cxx_unwind.c src/cxx_threads.c src/wchar.c src/tlv.c
OBJ = $(SRC:.c=.o) src/objc/msgsend.o src/objc/unwind.o
TBD = sdk/lib/libSystem.tbd sdk/lib/libobjc.tbd
# Link stubs for the Mac libraries served by this system's copy (src/host.c).
TWIN_TBD = sdk/lib/libz.tbd sdk/lib/libbz2.tbd sdk/lib/liblzma.tbd sdk/lib/libxml2.tbd sdk/lib/libsqlite3.tbd \
           sdk/lib/libicucore.tbd sdk/lib/libc++.tbd sdk/lib/libc++abi.tbd

# Ferry's own Foundation, built as a Mac library with ferry-cc (needs clang
# and lld, as the tests do). CoreFoundation is served from the same file.
FOUNDATION_SRC = $(wildcard foundation/*.m)
FOUNDATION_OBJ = $(FOUNDATION_SRC:foundation/%.m=foundation/build/%.o)
FOUNDATION = frameworks/Foundation.framework/Foundation
FOUNDATION_HEADERS = foundation/FInternal.h sdk/include/Foundation/Foundation.h \
                     sdk/include/CoreFoundation/CoreFoundation.h sdk/include/SystemConfiguration/SystemConfiguration.h \
                     $(wildcard sdk/include/Foundation/NS*.h) \
                     sdk/include/CoreFoundation/CFSocket.h sdk/include/CoreFoundation/CFStream.h \
                     sdk/include/CoreFoundation/CFMore.h sdk/include/CoreFoundation/CFSet.h sdk/include/CoreFoundation/CFLocale.h sdk/include/CoreFoundation/CFDate.h \
                     sdk/include/CoreFoundation/CFError.h \
                     sdk/include/CFNetwork/CFNetwork.h $(wildcard sdk/include/CoreServices/*.h) foundation/UTCoreTypes.inc \
                     sdk/include/IOKit/IOKitLib.h sdk/include/IOKit/IOReturn.h sdk/include/IOKit/pwr_mgt/IOPMLib.h \
                     foundation/FCurl.h foundation/FURLInternal.h foundation/FExpression.h
OBJCFLAGS = -O2 -g -Wall -Wno-unused-parameter -fno-modules

# Core Graphics and Core Text (M3), one Mac library that draws with this
# system's Cairo and Pango. CoreText, ApplicationServices and ImageIO are served from
# it, as CoreFoundation is from Foundation.
GRAPHICS_SRC = $(wildcard graphics/*.m)
GRAPHICS_OBJ = $(GRAPHICS_SRC:graphics/%.m=graphics/build/%.o)
GRAPHICS = frameworks/CoreGraphics.framework/CoreGraphics
GRAPHICS_HEADERS = graphics/GInternal.h graphics/host.h sdk/include/CoreGraphics/CoreGraphics.h \
                   sdk/include/CoreGraphics/CGEvent.h sdk/include/CoreGraphics/CGWindow.h \
                   sdk/include/CoreText/CoreText.h sdk/include/ImageIO/ImageIO.h $(FOUNDATION_HEADERS)
HOST_TBD = graphics/build/libFerryHost.tbd

# Core Animation (QuartzCore): layers drawn with the library above and
# animated on the main run loop.
QUARTZCORE_SRC = $(wildcard quartzcore/*.m)
QUARTZCORE_OBJ = $(QUARTZCORE_SRC:quartzcore/%.m=quartzcore/build/%.o)
QUARTZCORE = frameworks/QuartzCore.framework/QuartzCore
QUARTZCORE_HEADERS = quartzcore/QInternal.h $(wildcard sdk/include/QuartzCore/*.h) $(GRAPHICS_HEADERS)

# Security: keychain items in the user's own files, code signing answers
# and certificate trust through this system's OpenSSL.
SECURITY_SRC = $(wildcard security/*.m)
SECURITY_OBJ = $(SECURITY_SRC:security/%.m=security/build/%.o)
SECURITY = frameworks/Security.framework/Security
SECURITY_HEADERS = security/SInternal.h $(wildcard sdk/include/Security/*.h) $(wildcard sdk/include/CommonCrypto/*.h) \
                   $(FOUNDATION_HEADERS)

# AppKit (M4): windows through this system's GTK, drawn with the library
# above. Cocoa is served from it.
APPKIT_SRC = $(wildcard appkit/*.m)
APPKIT_OBJ = $(APPKIT_SRC:appkit/%.m=appkit/build/%.o)
APPKIT = frameworks/AppKit.framework/AppKit
APPKIT_HEADERS = appkit/AInternal.h appkit/gtk.h sdk/include/AppKit/AppKit.h $(QUARTZCORE_HEADERS) \
                 appkit/ANotify.h sdk/include/AppKit/NSDockTile.h sdk/include/UserNotifications/UserNotifications.h \
                 sdk/include/AppKit/NSCollectionView.h sdk/include/AppKit/NSRulerView.h \
                 appkit/AWayfire.h sdk/include/AppKit/NSEventMonitors.h sdk/include/HIServices/Accessibility.h \
                 sdk/include/Carbon/Carbon.h sdk/include/ScriptingBridge/ScriptingBridge.h \
                 $(wildcard sdk/include/AppKit/*.h)

# CloudKit: records, zones and subscriptions as plain objects, with no
# iCloud account behind them (cloudkit/CloudKit.m).
CLOUDKIT_SRC = $(wildcard cloudkit/*.m)
CLOUDKIT_OBJ = $(CLOUDKIT_SRC:cloudkit/%.m=cloudkit/build/%.o)
CLOUDKIT = frameworks/CloudKit.framework/CloudKit
CLOUDKIT_HEADERS = sdk/include/CloudKit/CloudKit.h $(FOUNDATION_HEADERS)

# Ferry's own Installer (installer/), a Mac app built against the frameworks above.
INSTALLER_SRC = installer/Installer.m installer/IPackage.m
INSTALLER_APP = installer/Installer.app
INSTALLER = $(INSTALLER_APP)/Contents/MacOS/Installer

# Core Data: models, contexts and stores (SQLite on this system's SQLite,
# binary and in memory).
COREDATA_SRC = $(wildcard coredata/*.m)
COREDATA_OBJ = $(COREDATA_SRC:coredata/%.m=coredata/build/%.o)
COREDATA = frameworks/CoreData.framework/CoreData
COREDATA_HEADERS = coredata/CDInternal.h sdk/include/CoreData/CoreData.h $(FOUNDATION_HEADERS)

# WebKit: web views shown by this system's WebKitGTK, which is opened only
# when a program first makes one (src/host.c), inside AppKit's windows.
WEBKIT_SRC = $(wildcard webkit/*.m)
WEBKIT_OBJ = $(WEBKIT_SRC:webkit/%.m=webkit/build/%.o)
WEBKIT = frameworks/WebKit.framework/WebKit
WEBKIT_HEADERS = webkit/WKInternal.h webkit/WKHost.h $(wildcard sdk/include/WebKit/*.h) $(APPKIT_HEADERS)

# JavaScriptCore: its C API passed to this system's JavaScriptCore, which is
# opened when a program first makes a call (src/host.c), and the
# Objective-C API built on it.
JSC_SRC = $(wildcard javascriptcore/*.m)
JSC_OBJ = $(JSC_SRC:javascriptcore/%.m=javascriptcore/build/%.o)
JSC = frameworks/JavaScriptCore.framework/JavaScriptCore
JSC_HEADERS = javascriptcore/JSCNames.h $(wildcard sdk/include/JavaScriptCore/*.h) $(FOUNDATION_HEADERS)

all: ferry $(TBD) $(TWIN_TBD) $(FOUNDATION) $(GRAPHICS) $(QUARTZCORE) $(SECURITY) $(APPKIT) $(INSTALLER) $(COREDATA) $(WEBKIT) $(JSC) $(CLOUDKIT)

ferry: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $(OBJ) $(LDLIBS)

src/%.o: src/%.c src/ferry.h src/macho.h src/objc/objc-private.h
	$(CC) $(CFLAGS) -c -o $@ $<

# C++ programs (src/cxx.c): this system's libc++, opened when a program links it.
src/cxx.o src/cxx_unwind.o src/cxx_threads.o src/lookup.o src/loader.o src/objc/exception.o: src/cxx.h

# The Cairo, Pango, HarfBuzz, GTK, GdkPixbuf and Poppler calls Ferry's frameworks may make:
# exactly the ones graphics/host.h and appkit/gtk.h declare.
src/host_names.h: graphics/host.h appkit/gtk.h webkit/WKHost.h
	cat $^ | grep -oE '\b(cairo|pango|g|hb|gtk|gdk|poppler)_[a-z0-9_]+\(' | tr -d '(' | sort -u | sed 's/.*/    "&",/' > $@

src/host.o: src/host_names.h src/webkit_names.h src/jsc_names.h

# The WebKitGTK and JavaScriptCore calls Ferry's WebKit may look up by name:
# exactly the ones webkit/WKHost.h declares.
src/webkit_names.h: webkit/WKHost.h
	grep -oE '\b(webkit|jsc)_[a-z0-9_]+\(' $^ | tr -d '(' | sort -u | sed 's/.*/    "&",/' > $@

# The JavaScriptCore calls Ferry's JavaScriptCore may look up by name:
# exactly the ones javascriptcore/JSCNames.h lists.
src/jsc_names.h: javascriptcore/JSCNames.h
	grep -oE 'X\(JS[A-Za-z0-9]+\)' $^ | sed 's/X(\(.*\))/    "\1",/' > $@

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

# A Mac's libc++ and libc++abi, served by this system's LLVM libc++ (empty
# when it isn't installed: C++ programs can't be built then).
sdk/lib/libc++.tbd: sdk/gen-cxx-tbd.sh
	@mkdir -p sdk/lib
	sdk/gen-cxx-tbd.sh libc++ > $@
sdk/lib/libc++abi.tbd: sdk/gen-cxx-tbd.sh
	@mkdir -p sdk/lib
	sdk/gen-cxx-tbd.sh libc++abi > $@

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
	@mkdir -p frameworks/CoreServices.framework
	sdk/gen-alias-tbd.sh CoreServices $@ > frameworks/CoreServices.framework/CoreServices.tbd
	@mkdir -p frameworks/ServiceManagement.framework
	sdk/gen-alias-tbd.sh ServiceManagement $@ > frameworks/ServiceManagement.framework/ServiceManagement.tbd
	@mkdir -p frameworks/CFNetwork.framework
	sdk/gen-alias-tbd.sh CFNetwork $@ > frameworks/CFNetwork.framework/CFNetwork.tbd
	@mkdir -p frameworks/IOKit.framework
	sdk/gen-alias-tbd.sh IOKit $@ > frameworks/IOKit.framework/IOKit.tbd

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

security/build/%.o: security/%.m $(SECURITY_HEADERS) sdk/ferry-cc
	@mkdir -p security/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

$(SECURITY): $(SECURITY_OBJ) $(FOUNDATION)
	@mkdir -p frameworks/Security.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/Security.framework/Versions/A/Security \
	    -o $@ $(SECURITY_OBJ) -framework Foundation

appkit/build/%.o: appkit/%.m $(APPKIT_HEADERS) sdk/ferry-cc
	@mkdir -p appkit/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

$(APPKIT): $(APPKIT_OBJ) $(GRAPHICS) $(QUARTZCORE) $(HOST_TBD)
	@mkdir -p frameworks/AppKit.framework frameworks/Cocoa.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit \
	    -o $@ $(APPKIT_OBJ) -framework Foundation -framework CoreGraphics -framework QuartzCore $(HOST_TBD)
	sdk/gen-alias-tbd.sh Cocoa $@ $(FOUNDATION) $(GRAPHICS) > frameworks/Cocoa.framework/Cocoa.tbd
	@mkdir -p frameworks/Carbon.framework
	sdk/gen-alias-tbd.sh Carbon $@ $(FOUNDATION) > frameworks/Carbon.framework/Carbon.tbd
	@mkdir -p frameworks/UserNotifications.framework
	sdk/gen-alias-tbd.sh UserNotifications $@ > frameworks/UserNotifications.framework/UserNotifications.tbd
	@mkdir -p frameworks/ScriptingBridge.framework
	sdk/gen-alias-tbd.sh ScriptingBridge $@ > frameworks/ScriptingBridge.framework/ScriptingBridge.tbd
	@mkdir -p frameworks/Quartz.framework frameworks/QuickLook.framework
	sdk/gen-alias-tbd.sh Quartz $@ > frameworks/Quartz.framework/Quartz.tbd
	sdk/gen-alias-tbd.sh QuickLook $@ > frameworks/QuickLook.framework/QuickLook.tbd
	# Quartz window and event services live in AppKit's file (CGServices.m),
	# so ApplicationServices offers them too
	sdk/gen-alias-tbd.sh ApplicationServices $(GRAPHICS) $@ $(FOUNDATION) > frameworks/ApplicationServices.framework/ApplicationServices.tbd

$(INSTALLER): $(INSTALLER_SRC) installer/IPackage.h installer/Info.plist $(APPKIT) $(TWIN_TBD)
	@mkdir -p $(INSTALLER_APP)/Contents/MacOS
	cp installer/Info.plist $(INSTALLER_APP)/Contents/Info.plist
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -o $@ $(INSTALLER_SRC) -framework Cocoa -lz -llzma

coredata/build/%.o: coredata/%.m $(COREDATA_HEADERS) sdk/ferry-cc
	@mkdir -p coredata/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

$(COREDATA): $(COREDATA_OBJ) $(FOUNDATION) $(TWIN_TBD)
	@mkdir -p frameworks/CoreData.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/CoreData.framework/Versions/A/CoreData \
	    -o $@ $(COREDATA_OBJ) -framework Foundation -lsqlite3

webkit/build/%.o: webkit/%.m $(WEBKIT_HEADERS) sdk/ferry-cc
	@mkdir -p webkit/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

$(WEBKIT): $(WEBKIT_OBJ) $(APPKIT) $(HOST_TBD)
	@mkdir -p frameworks/WebKit.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/WebKit.framework/Versions/A/WebKit \
	    -o $@ $(WEBKIT_OBJ) -framework Foundation -framework CoreGraphics -framework AppKit $(HOST_TBD)

javascriptcore/build/%.o: javascriptcore/%.m $(JSC_HEADERS) sdk/ferry-cc
	@mkdir -p javascriptcore/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

$(JSC): $(JSC_OBJ) $(FOUNDATION) $(GRAPHICS)
	@mkdir -p frameworks/JavaScriptCore.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/JavaScriptCore \
	    -o $@ $(JSC_OBJ) -framework Foundation -framework CoreGraphics

cloudkit/build/%.o: cloudkit/%.m $(CLOUDKIT_HEADERS) sdk/ferry-cc
	@mkdir -p cloudkit/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

$(CLOUDKIT): $(CLOUDKIT_OBJ) $(FOUNDATION)
	@mkdir -p frameworks/CloudKit.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/CloudKit.framework/Versions/A/CloudKit \
	    -o $@ $(CLOUDKIT_OBJ) -framework Foundation

check: all
	./tests/run.sh

install: ferry $(TBD) $(TWIN_TBD) $(FOUNDATION) $(GRAPHICS) $(QUARTZCORE) $(SECURITY) $(APPKIT) $(INSTALLER) $(COREDATA) $(WEBKIT) $(JSC) $(CLOUDKIT)
	install -Dm755 $(INSTALLER) $(DESTDIR)$(PREFIX)/lib/ferry/Installer.app/Contents/MacOS/Installer
	install -Dm644 $(INSTALLER_APP)/Contents/Info.plist $(DESTDIR)$(PREFIX)/lib/ferry/Installer.app/Contents/Info.plist
	install -Dm644 packaging/ferry-installer.desktop $(DESTDIR)$(PREFIX)/share/applications/ferry-installer.desktop
	install -Dm755 ferry $(DESTDIR)$(PREFIX)/bin/ferry
	install -Dm755 sdk/ferry-cc $(DESTDIR)$(PREFIX)/bin/ferry-cc
	install -Dm755 sdk/ferry-ibtool $(DESTDIR)$(PREFIX)/bin/ferry-ibtool
	install -d $(DESTDIR)$(PREFIX)/share/ferry/sdk
	cp -r sdk/include sdk/lib $(DESTDIR)$(PREFIX)/share/ferry/sdk/
	install -Dm755 $(FOUNDATION) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/Foundation.framework/Foundation
	install -Dm644 frameworks/CoreFoundation.framework/CoreFoundation.tbd \
	    $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/CoreFoundation.framework/CoreFoundation.tbd
	install -Dm755 $(GRAPHICS) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/CoreGraphics.framework/CoreGraphics
	install -Dm755 $(QUARTZCORE) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/QuartzCore.framework/QuartzCore
	install -Dm755 $(SECURITY) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/Security.framework/Security
	install -Dm755 $(APPKIT) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/AppKit.framework/AppKit
	for f in CoreText ApplicationServices ImageIO Cocoa SystemConfiguration Carbon CoreServices CFNetwork ServiceManagement IOKit UserNotifications ScriptingBridge Quartz QuickLook; do \
	    install -Dm644 frameworks/$$f.framework/$$f.tbd $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/$$f.framework/$$f.tbd; \
	done
	install -Dm644 binfmt/ferry.conf $(DESTDIR)$(PREFIX)/lib/binfmt.d/ferry.conf
	install -Dm755 $(COREDATA) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/CoreData.framework/CoreData
	install -Dm755 $(WEBKIT) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/WebKit.framework/WebKit
	install -Dm755 $(JSC) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/JavaScriptCore.framework/JavaScriptCore
	install -Dm755 $(CLOUDKIT) $(DESTDIR)$(PREFIX)/lib/ferry/frameworks/CloudKit.framework/CloudKit

clean:
	rm -f ferry $(OBJ) $(TBD) src/host_names.h src/webkit_names.h src/jsc_names.h
	rm -rf tests/build foundation/build graphics/build quartzcore/build security/build appkit/build frameworks \
	    installer/Installer.app coredata/build webkit/build javascriptcore/build cloudkit/build

.PHONY: all check install clean
