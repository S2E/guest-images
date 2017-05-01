#!/usr/bin/env python

"""
Copyright (c) 2017, Cyberhaven

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

from __future__ import print_function

import argparse
import magic
import os
import sys

g_m = None

# Accomodate older versions of magic (ubuntu 14.04)
def detect_magic():
    global g_m
    if hasattr(magic, 'open'):
        g_m = magic.open(magic.MAGIC_SYMLINK)
        g_m.load()

def get_magic(filename):
    if g_m:
        return g_m.file(filename)
    else:
        return magic.from_file(filename)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('path', type=str, nargs=1, help='Path to folder')

    args = parser.parse_args()
    path = args.path[0]

    detect_magic()

    if not os.path.isdir(path):
        print('Path %s is not a directory' % output)
        sys.exit(-1)

    for root, dirs, files in os.walk(path, topdown=False):
        hasfiles = False

        # Delete all non-executable files in this dir
        for fname in files:
            fpath = os.path.join(root, fname)
            if os.path.isfile(fpath):
                m = get_magic(fpath)
                if 'executable' in m:
                    hasfiles = True
                    continue
            os.remove(fpath)

        if not hasfiles and root != path:
            # Check if we still have subdirs that we
            # haven't deleted before
            for dname in dirs:
                if os.path.exists(os.path.join(root, dname)):
                    break
            else:
                os.rmdir(root)

if __name__ == '__main__':
    main()
