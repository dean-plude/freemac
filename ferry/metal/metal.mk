# SPDX-License-Identifier: GPL-3.0-or-later
# Ferry's Metal.framework: the device, shader libraries, pipelines, command
# buffers and the drawing engine in metal/fw, and the shader compiler
# (metal/ferry-mslc with the shader language headers in metal/msl), which
# it runs to build a program's shaders. Included from media/media.mk.
METAL_FW_SRC = $(wildcard metal/fw/*.m) $(wildcard metal/fw/*.c)
METAL_FW_OBJ = $(patsubst metal/fw/%,metal/build/%.o,$(METAL_FW_SRC))
METAL_FW_HEADERS = $(wildcard metal/fw/*.h) metal/msl/ferry_metal_abi.h $(wildcard sdk/include/Metal/*.h) $(FOUNDATION_HEADERS)

metal/build/%.m.o: metal/fw/%.m $(METAL_FW_HEADERS) sdk/ferry-cc
	@mkdir -p metal/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

metal/build/%.c.o: metal/fw/%.c $(METAL_FW_HEADERS) sdk/ferry-cc
	@mkdir -p metal/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

frameworks/Metal.framework/Metal: $(METAL_FW_OBJ) $(FOUNDATION) $(GRAPHICS)
	@mkdir -p frameworks/Metal.framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/Metal.framework/Versions/A/Metal \
	    -o $@ $(METAL_FW_OBJ) -framework Foundation -framework CoreGraphics

# The shader compiler and its headers, next to the frameworks.
install-metal:
	install -Dm755 metal/ferry-mslc $(DESTDIR)$(PREFIX)/lib/ferry/metal/ferry-mslc
	install -Dm755 metal/ferry-airc $(DESTDIR)$(PREFIX)/lib/ferry/metal/ferry-airc
	install -d $(DESTDIR)$(PREFIX)/lib/ferry/metal/msl
	install -m644 $(filter-out metal/msl/simd,$(wildcard metal/msl/*)) $(DESTDIR)$(PREFIX)/lib/ferry/metal/msl/
	install -Dm644 metal/msl/simd/simd.h $(DESTDIR)$(PREFIX)/lib/ferry/metal/msl/simd/simd.h

.PHONY: install-metal
