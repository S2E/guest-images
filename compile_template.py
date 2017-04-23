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

import optparse
import json
import sys


def main():
    usage = 'usage: %prog [options] [var1=value1 [var2=value2 ...]]'
    parser = optparse.OptionParser(usage=usage)
    parser.add_option('-i', dest='template', metavar='FILE',
                      help='Input template')
    parser.add_option('-o', dest='output', metavar='FILE',
                      help='Output file')
    parser.add_option('-n', dest='image_name',
                      help='Image name')

    (options, args) = parser.parse_args()

    context = {}
    for arg in args:
        if '=' not in arg:
            parser.error('cannot parse var %s' % arg)
        k, v = arg.split('=', 1)
        context[k] = v

    # Get image descriptor template
    if options.template:
        with open(options.template, 'r') as f:
            template = json.loads(f.read())
    else:
        template = json.loads(sys.stdin.read())

    template = template['images']

    if options.image_name not in template.keys():
        print('%s does not exist in %s' % (options.image_name, options.template))
        sys.exit(-1)

    template = template[options.image_name]

    descriptor = {
        'os_name':    template['os_name'],
        'os_version': template['os_version'],
        'os_arch':    template['os_arch'],
        'os_build':   template['os_build'],
        'os_binary_formats': template['os_binary_formats'],

        'memory':     context['memory'],
        'qemu_extra_flags': context['qemu_extra_flags'],
        'qemu_build': context['qemu_build'],
        'snapshot': context['snapshot']
    }

    output = json.dumps(descriptor, indent=4, sort_keys=True)

    if options.output:
        with open(options.output, 'w') as f:
            f.write(output)
    else:
        sys.stdout.write(output)


if __name__ == '__main__':
    main()
