#---------------------------------------------------------------------------------
# gen2recomp Switch native OTA launcher
# Requires: DEVKITPRO + switch-curl, switch-mbedtls, switch-zlib, switch-zziplib
# Host protocol tests: make host-test (no DEVKITPRO needed)
#---------------------------------------------------------------------------------
.SUFFIXES:

#---------------------------------------------------------------------------------
# Host-only path when DEVKITPRO is unset
#---------------------------------------------------------------------------------
ifeq ($(strip $(DEVKITPRO)),)

.PHONY: host-test clean-host
host-test:
	@mkdir -p build-host
	cc -std=c11 -Wall -Wextra -Iinclude -o build-host/test_ota_protocol \
		src/ota_protocol.c host/test_ota_protocol.c
	./build-host/test_ota_protocol

clean-host:
	rm -rf build-host

%:
	@echo "DEVKITPRO not set — only 'make host-test' is available."
	@echo "Run: bash scripts/switch/install_devkitpro_deps.sh"
	@false

else

#---------------------------------------------------------------------------------
TOPDIR ?= $(CURDIR)
include $(DEVKITPRO)/libnx/switch_rules

#---------------------------------------------------------------------------------
TARGET		:=	gen2recomp
BUILD		:=	build
SOURCES		:=	src
DATA		:=	data
INCLUDES	:=	include
ROMFS		:=	romfs

APP_TITLE	:=	gen2recomp
APP_AUTHOR	:=	UNDERdecodedHD, port by andrewqsantos
# Overridable: scripts/switch/build_ota_launcher.sh passes release X.Y.Z
APP_VERSION	?=	0.0.0

# Prefer project Switch icon if present
ICON		:=	$(TOPDIR)/../assets/icon.jpg
LOGO_RGBA_SRC	:=	$(TOPDIR)/../assets/logo.rgba
LOGO_ROMFS	:=	$(CURDIR)/$(ROMFS)/logo.rgba

#---------------------------------------------------------------------------------
ARCH	:=	-march=armv8-a+crc+crypto -mtune=cortex-a57 -mtp=soft -fPIE

CFLAGS	:=	-g -Wall -O2 -ffunction-sections $(ARCH) $(DEFINES)
CFLAGS	+=	$(INCLUDE) -D__SWITCH__

CXXFLAGS	:= $(CFLAGS) -fno-rtti -fno-exceptions

ASFLAGS	:=	-g $(ARCH)
LDFLAGS	=	-specs=$(DEVKITPRO)/libnx/switch.specs -g $(ARCH) -Wl,-Map,$(notdir $*.map)

LIBS	:=	-lcurl -lzzip -lmbedtls -lmbedx509 -lmbedcrypto -lz -lnx

LIBDIRS	:= $(PORTLIBS) $(LIBNX)

#---------------------------------------------------------------------------------
ifneq ($(BUILD),$(notdir $(CURDIR)))
#---------------------------------------------------------------------------------

export OUTPUT	:=	$(CURDIR)/$(TARGET)
export TOPDIR	:=	$(CURDIR)

export VPATH	:=	$(foreach dir,$(SOURCES),$(CURDIR)/$(dir)) \
			$(foreach dir,$(DATA),$(CURDIR)/$(dir))

export DEPSDIR	:=	$(CURDIR)/$(BUILD)

CFILES		:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.c)))
CPPFILES	:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.cpp)))
SFILES		:=	$(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.s)))
BINFILES	:=	$(foreach dir,$(DATA),$(notdir $(wildcard $(dir)/*.*)))

#---------------------------------------------------------------------------------
# use CXX for linking C++ projects, CC for standard C
#---------------------------------------------------------------------------------
ifeq ($(strip $(CPPFILES)),)
	export LD	:=	$(CC)
else
	export LD	:=	$(CXX)
endif
#---------------------------------------------------------------------------------

export OFILES_BIN	:=	$(addsuffix .o,$(BINFILES))
export OFILES_SRC	:=	$(CPPFILES:.cpp=.o) $(CFILES:.c=.o) $(SFILES:.s=.o)
export OFILES 	:=	$(OFILES_BIN) $(OFILES_SRC)

export INCLUDE	:=	$(foreach dir,$(INCLUDES),-I$(CURDIR)/$(dir)) \
			$(foreach dir,$(LIBDIRS),-I$(dir)/include) \
			-I$(CURDIR)/$(BUILD)

export LIBPATHS	:=	$(foreach dir,$(LIBDIRS),-L$(dir)/lib)

ifeq ($(strip $(ICON)),)
	icons := $(wildcard *.jpg)
	ifneq (,$(findstring $(TARGET).jpg,$(icons)))
		export APP_ICON := $(TOPDIR)/$(TARGET).jpg
	else
		ifneq (,$(findstring icon.jpg,$(icons)))
			export APP_ICON := $(TOPDIR)/icon.jpg
		endif
	endif
else
	ifeq ($(wildcard $(ICON)),)
		# fall back to libnx default if project icon missing
		export APP_ICON := $(LIBNX)/default_icon.jpg
	else
		export APP_ICON := $(ICON)
	endif
endif

ifeq ($(strip $(NO_ICON)),)
	export NROFLAGS += --icon=$(APP_ICON)
endif

ifeq ($(strip $(NO_NACP)),)
	export NROFLAGS += --nacp=$(CURDIR)/$(TARGET).nacp
endif

ifneq ($(ROMFS),)
	export NROFLAGS += --romfsdir=$(CURDIR)/$(ROMFS)
endif

BOOTSTRAP_DIR	:=	$(TOPDIR)/../ota-bootstrap
BOOTSTRAP_ROMFS	:=	$(CURDIR)/$(ROMFS)/ota-bootstrap.nro

.PHONY: $(BUILD) clean all host-test sync-romfs bootstrap-romfs

#---------------------------------------------------------------------------------
all: sync-romfs $(BUILD)

CACERT_URL	:=	https://curl.se/ca/cacert.pem
CACERT_ROMFS	:=	$(CURDIR)/$(ROMFS)/cacert.pem

bootstrap-romfs:
	@$(MAKE) --no-print-directory -C $(BOOTSTRAP_DIR) all
	@mkdir -p $(CURDIR)/$(ROMFS)
	@cp -f $(BOOTSTRAP_DIR)/ota-bootstrap.nro $(BOOTSTRAP_ROMFS)

sync-romfs: bootstrap-romfs
	@mkdir -p $(CURDIR)/$(ROMFS)
	@[ -f "$(LOGO_RGBA_SRC)" ] || (echo "missing $(LOGO_RGBA_SRC) — run: python3 scripts/switch/bake_ota_logo.py" && exit 1)
	@cp -f "$(LOGO_RGBA_SRC)" "$(LOGO_ROMFS)"
	@if ! curl -sfL --time-cond $(CACERT_ROMFS) -o $(CACERT_ROMFS) $(CACERT_URL); then \
		[ -f $(CACERT_ROMFS) ] || (echo "sync-romfs: failed to fetch cacert.pem" && exit 1); \
	fi

$(BUILD): sync-romfs
	@[ -d $@ ] || mkdir -p $@
	@$(MAKE) --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile

#---------------------------------------------------------------------------------
clean:
	@echo clean ...
	@$(MAKE) --no-print-directory -C $(BOOTSTRAP_DIR) clean || true
	@rm -fr $(BUILD) $(TARGET).nro $(TARGET).nacp $(TARGET).elf $(TARGET).lst build-host
	@rm -f $(CURDIR)/$(ROMFS)/logo.rgba $(CURDIR)/$(ROMFS)/logo.png

host-test:
	@mkdir -p build-host
	cc -std=c11 -Wall -Wextra -Iinclude -o build-host/test_ota_protocol \
		src/ota_protocol.c host/test_ota_protocol.c
	./build-host/test_ota_protocol

#---------------------------------------------------------------------------------
else
.PHONY: all

DEPENDS	:=	$(OFILES:.o=.d)

#---------------------------------------------------------------------------------
all: $(OUTPUT).nro

$(OUTPUT).nro: $(OUTPUT).elf $(OUTPUT).nacp

$(OUTPUT).elf: $(OFILES)

-include $(DEPENDS)

#---------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------
endif
