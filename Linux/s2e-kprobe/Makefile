# Copyright (c) 2024 IBM Corporation
#
# Author: Andrea Mambretti <amb@zurich.ibm.com>
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

CONFIG_MODULE_SIG=n
KASAN_SANITIZE := n


# if KERNELRELEASE is defined, we've been invoked from the kernel build system and can use its language.
ifneq (${KERNELRELEASE},)
	obj-m := s2e-kprobe.o
	EXTRA_CFLAGS :="-I$(PWD)/include"
# Otherwise we were called directly from the command line.
# Invoke the kernel build system.
else
	PWD := $(shell pwd)

default:
	$(CFLAGS) $(MAKE) -C $(KERNELPATH) src=$(PWD) M=$(PWD)/s2e-$(KERNELFULL) modules
clean:
	$(MAKE) -C $(KERNELPATH) src=$(PWD) M=$(PWD)/s2e-$(KERNELFULL) clean
install:
	sudo insmod s2e-kprobe.ko
rm:
	sudo rmmod s2e-kprobe
endif

