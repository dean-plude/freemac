# SPDX-License-Identifier: GPL-3.0-or-later
# Mac frameworks for graphics and media programs (OBS, through Qt):
# Accelerate (vImage), Metal (no device), DiskArbitration (no disks) and
# Network (the path monitor). Each is one source file in media/ and its own
# framework file; included from Ferry's Makefile.
MEDIA_FW = Accelerate Metal DiskArbitration Network
MEDIA = $(foreach f,$(MEDIA_FW),frameworks/$(f).framework/$(f))
MEDIA_HEADERS = sdk/include/Accelerate/Accelerate.h \
                sdk/include/Metal/Metal.h sdk/include/DiskArbitration/DiskArbitration.h \
                sdk/include/Network/Network.h $(FOUNDATION_HEADERS)

all: $(MEDIA)

media/build/%.o: media/%.m $(MEDIA_HEADERS) sdk/ferry-cc
	@mkdir -p media/build
	sdk/ferry-cc $(OBJCFLAGS) -fblocks -c -o $@ $<

define MEDIA_RULE
frameworks/$(1).framework/$(1): media/build/$(1).o $$(FOUNDATION) $$(GRAPHICS)
	@mkdir -p frameworks/$(1).framework
	sdk/ferry-cc -dynamiclib -install_name /System/Library/Frameworks/$(1).framework/Versions/A/$(1) \
	    -o $$@ $$< -framework Foundation -framework CoreGraphics
endef
$(foreach f,$(MEDIA_FW),$(eval $(call MEDIA_RULE,$(f))))
