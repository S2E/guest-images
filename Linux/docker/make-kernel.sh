#!/bin/bash
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

#
# Usage: ./make-kernel.sh s2e_include_path UID GID
#

if [ $# -ne 3 ]; then
    echo "Usage: ./make-kernel.sh s2e_include_path uid gid"
    exit 1
fi

MUID=$2
MGID=$3

groupadd -g $MGID s2e
useradd -u $MUID -g s2e s2e

# Run the rest of the script with the uid/gid provided, otherwise
# new files will be owned by root.
exec sudo -u s2e /bin/bash - << EOF

export C_INCLUDE_PATH=${1}:${C_INCLUDE_PATH}

if [ ! -e .config ]; then
    echo "No .config - generating the default config"
    make defconfig
else
    echo "Using existing .config"
fi


# NOTE: you have to run this inside special docker image (see run-docker.sh)
make-kpkg --initrd --append-to-version s2e --jobs 8 --rootcmd fakeroot  kernel-image kernel-debug || err "Build failed"

# Restore access to files under version control
chmod a+rw debian

# Restore access to useful files
chmod a+rw vmlinux

EOF