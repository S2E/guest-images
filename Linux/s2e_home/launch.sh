#!/bin/sh

# S2E Selective Symbolic Execution Platform
#
# Copyright (c) 2017, Dependable Systems Laboratory, EPFL
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

set -ex

export DEBIAN_FRONTEND=noninteractive

# libelf is required for s2e.so
COMMON_PACKAGES="gcc-multilib g++-multilib libc6-dev-i386 libelf1:i386"
DEBIAN12_PACKAGES="lib32stdc++-12-dev libdebuginfod-dev lib32stdc++6 libstdc++6:i386"

# systemtap
UBUNTU_PACKAGES="elfutils libdw-dev"

dist_version() {
    lsb_release -rs | cut -d '.' -f 1
}

dist_name() {
    lsb_release -is | tr '[:upper:]' '[:lower:]'
}

install_packages() {
    # Preserve environment (-E)
    DEBIAN_FRONTEND=noninteractive sudo -E apt-get -y install $*
}

remove_packages() {
    # Preserve environment (-E)
    DEBIAN_FRONTEND=noninteractive sudo -E apt-get purge -y cloud-init
}

remove_ubuntu_packages() {
    NAME=$(dist_name)
    if [ "x$NAME" = "xubuntu" ]; then
        remove_packages cloud-init
    fi
}

# Install 32-bit user space for 64-bit kernels
install_i386() {
    if uname -a | grep -q x86_64; then
        sudo dpkg --add-architecture i386
        sudo apt-get update

        install_packages ${COMMON_PACKAGES}

        NAME=$(dist_name)
        VER=$(dist_version)

        if [ "x$NAME" = "xdebian" ]; then
            install_packages ${DEBIAN12_PACKAGES}
        elif [ "x$NAME" = "xubuntu" ]; then
            install_packages ${DEBIAN12_PACKAGES} ${UBUNTU_PACKAGES}
        else
            echo "Unsupported distribution ${NAME} ${VER}"
            exit 1
        fi
    fi
}


# Install systemtap from source
# The one that's packaged does not support our kernel
# Note: systemtap requires a lot of memory to compile, so we need swap
install_systemtap() {
    git clone https://github.com/S2E/systemtap.git
    cd systemtap
    git checkout release-4.9
    cd ..

    mkdir systemtap-build
    cd systemtap-build
    ../systemtap/configure --disable-docs
    make -j4
    sudo make install
    cd ..
}

# Install kernels last, the cause downgrade of libc,
# which will cause issues when installing other packages
install_kernel() {
    sudo dpkg -i linux-image*.deb linux-headers*.deb

    MENU_ENTRY="$(sudo grep menuentry /boot/grub/grub.cfg  | grep s2e | cut -d "'" -f 2 | head -n 1)"
    echo "Default menu entry: $MENU_ENTRY"
    echo "GRUB_DEFAULT=\"1>$MENU_ENTRY\"" | sudo tee -a /etc/default/grub
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0"' | sudo tee -a /etc/default/grub
    sudo update-grub
}

sudo apt-get update
install_packages wget lsb-release
remove_ubuntu_packages

install_i386

install_systemtap

install_kernel

# QEMU will stop (-no-reboot)
sudo reboot
