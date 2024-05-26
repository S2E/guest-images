#!/bin/sh

# Copyright (c) 2018, Cyberhaven
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

# Install the prerequisites for cgc packages
install_apt_packages() {
    APT_PACKAGES="
    libtinfo5
    "

    sudo apt-get -y --force-yes install ${APT_PACKAGES}
}

# Set of packages required to build CGC binaries.
# The rest of the infrastructure is not installed because it uses an old version
# of Python and can't work anymore.
install_cgc_packages() {
    CGC_PACKAGES="
    binutils-cgc-i386_2.24-10551-cfe-rc8_i386.deb
    cgc2elf_10551-cfe-rc8_i386.deb
    libcgcef0_10551-cfe-rc8_i386.deb
    libcgcdwarf_10551-cfe-rc8_i386.deb
    libcgc_10551-cfe-rc8_i386.deb
    cgc-release-documentation_10560-cfe-rc8_all.deb
    libpov_10551-cfe-rc8_i386.deb
    clang-cgc_3.4-10551-cfe-rc8_i386.deb
    magic-cgc_10551-cfe-rc8_all.deb
    "

    local CUR_DIR
    CUR_DIR="$(pwd)"

    # Download packages in temp folder
    cd /tmp

    # Install the CGC packages
    for PACKAGE in ${CGC_PACKAGES}; do
        wget --no-check-certificate https://cgcdist.s3.amazonaws.com/release-final/deb/${PACKAGE}
        sudo dpkg -i --force-confnew ${PACKAGE}
        rm -f ${PACKAGE}
    done

    cd "$CUR_DIR"
}

install_apt_packages
install_cgc_packages
