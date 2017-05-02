# Copyright (c) 2017, Cyberhaven
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

SRC?=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))

### Beginning of user-adjustable variables ###

# Override these two variables with your actual settings
S2E_INSTALL_ROOT ?=
S2E_LINUX_KERNELS_ROOT ?=

# Comment out this variable to enable graphic output
GRAPHICS ?= -nographic -monitor null

# If your host does not support KVM, comment out this variable.
# Image creation will take much longer.
QEMU_KVM ?= -enable-kvm

# Snapshots have 256 MB of guest RAM
# You may increase or decrease this value as needed
SNAPSHOT_MEMORY ?= 256

# Size of the disk image
# You may increase or decrease this value as needed
DISK_SIZE ?= 4G

# Where to store final images
OUTPUT_DIR ?= $(SRC)/output

### End of user-adjustable variables ###

TMPOUT = .tmp-output
STAMPS = .stamps

ARCH = $(word 3, $(subst -, ,$(1)))
OS_VERSION = $(word 2, $(subst -, ,$(1)))
OS_NAME = $(word 1, $(subst -, ,$(1)))

QEMU_IMG = $(S2E_INSTALL_ROOT)/bin/qemu-img
QEMU64 = $(S2E_INSTALL_ROOT)/bin/qemu-system-x86_64

GETQEMU = $(S2E_INSTALL_ROOT)/bin/qemu-system-$(call ARCH,$(1))
GETLIBS2E = $(S2E_INSTALL_ROOT)/share/libs2e/libs2e-$(call ARCH,$(1)).so

SNAPSHOT_NETWORK = -net none -net nic,model=e1000

_INFO_MSG_COLOR := $(shell tput setaf 3)
_OK_MSG_COLOR := $(shell tput setaf 2)
_NO_COLOR := $(shell tput sgr0)

INFO_MSG = @echo "$(_INFO_MSG_COLOR)[`date`] $1$(_NO_COLOR)"
OK_MSG = @echo "$(_OK_MSG_COLOR)[`date`] $1$(_NO_COLOR)"

### Provisioning the initial image ###

define TEMPLATE_BASE_LINUX_IMAGE
 $(OUTPUT_DIR)/$1:
 $(TMPOUT)/$1:
	mkdir -p "$$@"

 $(TMPOUT)/$1/$1.iso: | $(TMPOUT)/$1
	$(call INFO_MSG,[$$@] Downloading disk image...)
	wget -O $$@ $2

 $(TMPOUT)/$1/install_files.iso: $(TMPOUT)/$1/$1.iso $(SRC)/Linux/bootcd/preseed.cfg
	$(call INFO_MSG,[$$@] Creating installation disk...)
	rm -Rf $(TMPOUT)/$1/install_files && mkdir -p $(TMPOUT)/$1/install_files
	7z x $(TMPOUT)/$1/$1.iso -o$(TMPOUT)/$1/install_files

	cd $(TMPOUT)/$1 && chmod -R u+rwx install_files

	cp "$(SRC)/Linux/bootcd/preseed.cfg" "$(TMPOUT)/$1/install_files"
	cp "$(SRC)/Linux/bootcd/isolinux.cfg" "$(TMPOUT)/$1/install_files/isolinux/"
	cp "$(SRC)/Linux/bootcd/txt-$(call ARCH,$1).cfg" "$(TMPOUT)/$1/install_files/isolinux/txt.cfg"

	cd $(TMPOUT)/$1/install_files && \
		md5sum `find -follow -type f` > md5sum.txt

	genisoimage -o "$$@" -r -J -no-emul-boot -boot-load-size 4 \
		-boot-info-table -b isolinux/isolinux.bin -c isolinux/boot.cat "$(TMPOUT)/$1/install_files"

  $(TMPOUT)/$1/image.raw: $(TMPOUT)/$1/install_files.iso
	$(call INFO_MSG,[$$@] Creating disk image...)
	$(QEMU_IMG) create -f raw $$@ $(DISK_SIZE)

	$(call INFO_MSG,[$$@] Running initial setup...)
	$(QEMU64) -m 1G -no-reboot $(GRAPHICS) $(QEMU_KVM) \
	    -drive if=ide,index=0,file=$$@,format=raw,cache=writeback \
	    -cdrom $(TMPOUT)/$1/install_files.iso \
	    -serial file:$(TMPOUT)/$1/serial.txt
endef

### Installing the kernel and S2E payload ###

define BUILD_S2E_IMAGE
  $(OUTPUT_DIR)/$2$1/image.raw.s2e:  $(TMPOUT)/$1/image.raw $(STAMPS)/$3 \
                                     $(SRC)/Linux/s2e_home/launch.sh $(SRC)/Linux/s2e_home/.bash_login \
                                     $(SRC)/Linux/override.conf
	mkdir -p $$(shell dirname $$@)
	cp "$$<" "$$@"

	$(call INFO_MSG,[$$@] Installing kernels...)
	virt-copy-in -a "$$@" $(TMPOUT)/$3/*.deb /home/s2e

	$(call INFO_MSG,[$$@] Installing payload...)
	virt-copy-in -a "$$@" $(SRC)/Linux/s2e_home/launch.sh $(SRC)/Linux/s2e_home/.bash_login /home/s2e/

	guestfish --rw -a "$$@" -i mkdir /etc/systemd/system/getty@tty1.service.d/
	virt-copy-in -a "$$@" $(SRC)/Linux/override.conf /etc/systemd/system/getty@tty1.service.d/

	$(call INFO_MSG,[$$@] Booting disk image...)
	$(QEMU64) -m 1G -no-reboot $(GRAPHICS) $(QEMU_KVM) \
	    -drive if=ide,index=0,file=$$@,format=raw,cache=writeback \
	    -serial file:$(OUTPUT_DIR)/$2$1/serial.txt

	virt-copy-in -a "$$@" $(S2E_INSTALL_ROOT)/bin/guest-tools32/* /home/s2e/
endef

### Snapshot creation ###

define TAKE_SNAPSHOT
  $(OUTPUT_DIR)/$2$1/image.raw.s2e.ready: $(OUTPUT_DIR)/$2$1/image.raw.s2e
	$(call INFO_MSG,[$$@] Creating snapshot...)
	LD_PRELOAD=$(call GETLIBS2E,$1) $(call GETQEMU,$1) -enable-kvm \
	    -drive if=ide,index=0,file=$$<,format=s2e,cache=writeback \
	    -serial file:$(OUTPUT_DIR)/$2$1/serial_ready.txt -enable-serial-commands $(SNAPSHOT_NETWORK) \
	    -m $(SNAPSHOT_MEMORY) $(GRAPHICS)

  $(OUTPUT_DIR)/$2$1/image.json: $(OUTPUT_DIR)/$2$1/image.raw.s2e.ready $(SRC)/images.json $(SRC)/compile_template.py
	$(call INFO_MSG,[$$@] Creating image descriptor...)
	$(SRC)/compile_template.py -i $(SRC)/images.json -o $$@ -n "$2$1" \
		snapshot="ready" qemu_build="$(call ARCH,$2$1)" memory="$(SNAPSHOT_MEMORY)" qemu_extra_flags="$(SNAPSHOT_NETWORK)"
endef

### Building Linux kernel ###

# This creates the base docker image inside which the kernel will be built
$(STAMPS)/linux-build-%:
	$(call INFO_MSG,[$@] Building docker image...)
	mkdir -p $(STAMPS)
	cd $(SRC)/Linux/docker && docker build -t linux-build-$(call ARCH,$@) -f Dockerfile.$(call ARCH,$@) .
	touch $@

# Build the kernel
define TEMPLATE_LINUX_KERNEL
  $(STAMPS)/$1-$2: $(STAMPS)/linux-build-$2
	$(call INFO_MSG,[$$@] Building kernel...)
	rsync -a $(S2E_LINUX_KERNELS_ROOT)/$1 $(TMPOUT)/$1-$2
	cd $(TMPOUT)/$1-$2/$1 && mv config-$2 .config
	$(SRC)/Linux/docker/run-docker.sh linux-build-$2 $(TMPOUT)/$1-$2/$1 $(SRC)/Linux/docker/make-kernel.sh $(S2E_LINUX_KERNELS_ROOT)/include $(shell id -u) $(shell id -g)
	touch $$@
endef

### Instantiating all build configurations ###

# Rules for building base images
$(eval $(call TEMPLATE_BASE_LINUX_IMAGE,debian-8.7.1-x86_64,http://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-8.7.1-amd64-netinst.iso))
$(eval $(call TEMPLATE_BASE_LINUX_IMAGE,debian-8.7.1-i386,http://cdimage.debian.org/debian-cd/current/i386/iso-cd/debian-8.7.1-i386-netinst.iso))

# Rules for building the kernels
$(eval $(call TEMPLATE_LINUX_KERNEL,decree-cgc-cfe,i386))
$(eval $(call TEMPLATE_LINUX_KERNEL,linux-4.9.3,i386))
$(eval $(call TEMPLATE_LINUX_KERNEL,linux-4.9.3,x86_64))

$(eval $(call BUILD_S2E_IMAGE,debian-8.7.1-i386,cgc_,decree-cgc-cfe-i386))
$(eval $(call TAKE_SNAPSHOT,debian-8.7.1-i386,cgc_))

$(eval $(call BUILD_S2E_IMAGE,debian-8.7.1-i386,,linux-4.9.3-i386))
$(eval $(call TAKE_SNAPSHOT,debian-8.7.1-i386,))

$(eval $(call BUILD_S2E_IMAGE,debian-8.7.1-x86_64,,linux-4.9.3-x86_64))
$(eval $(call TAKE_SNAPSHOT,debian-8.7.1-x86_64,))

### Top level rules ###

all-kernels: $(STAMPS)/decree-cgc-cfe-i386 $(STAMPS)/linux-4.9.3-i386 $(STAMPS)/linux-4.9.3-x86_64

$(OUTPUT_DIR)/%.tar.xz: $(OUTPUT_DIR)/%/image.json
	$(call INFO_MSG,[$@] Creating image archive...)
	cd $(OUTPUT_DIR) && tar cJf "$(shell basename $@)" "$(shell basename $(shell dirname $<))"


debian-8.7.1-x86_64: $(OUTPUT_DIR)/debian-8.7.1-x86_64/image.json
debian-8.7.1-i386: $(OUTPUT_DIR)/debian-8.7.1-i386/image.json
cgc_debian-8.7.1-i386: $(OUTPUT_DIR)/cgc_debian-8.7.1-i386/image.json

all: debian-8.7.1-x86_64 debian-8.7.1-i386 cgc_debian-8.7.1-i386

archive: $(OUTPUT_DIR)/debian-8.7.1-x86_64.tar.xz $(OUTPUT_DIR)/debian-8.7.1-i386.tar.xz $(OUTPUT_DIR)/cgc_debian-8.7.1-i386.tar.xz


ifeq ($(OUTPUT_DIR),$(SRC)/output)
CLEAN_DIR=$(OUTPUT_DIR)
else
CLEAN_DIR=$(OUTPUT_DIR)/*
endif

clean:
	rm -rf $(CLEAN_DIR) $(OUTPUT_DIR)/* $(TMPOUT) $(STAMPS)
