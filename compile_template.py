#!/usr/bin/env python

# Copyright (C) 2017, Cyberhaven
# All rights reserved.
#
# Licensed under the Cyberhaven Research License Agreement.

import optparse
import jinja2
import sys


def main():
    usage = 'usage: %prog [options] [var1=value1 [var2=value2 ...]]'
    parser = optparse.OptionParser(usage=usage)
    parser.add_option('-i', dest='template', metavar='FILE',
                      help='Input template')
    parser.add_option('-o', dest='output', metavar='FILE',
                      help='Output file')

    (options, args) = parser.parse_args()

    context = {}
    for arg in args:
        if '=' not in arg:
            parser.error('cannot parse var %s' % arg)
        k, v = arg.split('=', 1)
        context[k] = v

    if options.template:
        with open(options.template, 'r') as f:
            template = f.read()
    else:
        template = sys.stdin.read()

    template = jinja2.Template(template)
    output = template.render(**context)

    if options.output:
        with open(options.output, 'w') as f:
            f.write(output)
    else:
        sys.stdout.write(output)


if __name__ == '__main__':
    main()
