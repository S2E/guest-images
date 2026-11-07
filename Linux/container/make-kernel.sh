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
# Usage: ./make-kernel.sh s2e_include_path
#
# The script runs as container root, which rootless Podman maps to the calling
# user, so the build outputs belong to that user.
#

set -xe

if [ $# -ne 1 ]; then
    echo "Usage: ./make-kernel.sh s2e_include_path"
    exit 1
fi

export C_INCLUDE_PATH=${1}:${C_INCLUDE_PATH}

if [ ! -e .config ]; then
    echo "No .config - generating the default config"
    make defconfig
else
    echo "Using existing .config"
fi

# NOTE: you have to run this inside the linux-build container image (see run-container.sh)
TARGET=bindeb-pkg

JOBS=$(grep -c ^processor /proc/cpuinfo)
make -j$JOBS $TARGET LOCALVERSION=-s2e
