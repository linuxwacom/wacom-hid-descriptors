#!/bin/env python2
# -*- coding: utf-8 -*-

# Copyright © 2015 Wacom Technology Corp.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

"""Convert the HID descriptor contained in lsusb output to a hex dump.

The verbose output of the "lsusb" command on Linux can print out the HID
descriptor of some USB devices in a human-readable format. This output
contains all the necessary information to translate it back into the
original binary form for use with other tools.

Note that this tool is not designed to be used as part of a pipeline. It
cannot parse lsusb output in general and should only be fed the relevant
descriptor from a single device; it also prints raw binary data so feeding
the output to "hexdump" might also be useful. See the usage below for more
information.

Usage:
    lsusb -v -d <vid>:<pid> |                    \
    awk '/Endpoint Descriptor/                   \
         { REPORT=0 }                            \
         {                                       \
             if (length == 0) { REPORT = 0 }     \
             if (REPORT == 1) { print $0 }       \
         }                                       \
                                                 \
         /length is/                             \
         { REPORT=1 }' |                         \
    python lsusb_to_hex.py |                     \
    hexdump -C
"""

import sys
import re
import struct

def is_definition_expected(typ, tag):
	return typ == "Main" and (tag == "Input" or tag == "Output" or tag == "Feature")

def is_note_expected(typ, tag):
	return (typ == "Global" and tag == "Usage Page") or \
	       (typ == "Local" and  tag == "Usage") or \
	       (typ == "Main" and tag == "Collection") or \
	       (typ == "Global" and tag == "Unit") or \
	       (typ == "Global" and tag == "Unit Exponent") or \
	       (typ == "Local" and tag == "Usage Minimum") or \
	       (typ == "Local" and tag == "Usage Maximum")

def get_item(typ, tag, data):
	if typ == "Main":
		if   tag == "Input":          tag = 8
		elif tag == "Output":         tag = 9
		elif tag == "Feature":        tag = 11
		elif tag == "Collection":     tag = 10
		elif tag == "End Collection": tag = 12
		else: raise Exception("Unknown type {} for {} tag".format(tag, typ))
		typ = 0
	elif typ == "Global":
		if   tag == "Usage Page":       tag = 0
		elif tag == "Logical Minimum":  tag = 1
		elif tag == "Logical Maximum":  tag = 2
		elif tag == "Physical Minimum": tag = 3
		elif tag == "Physical Maximum": tag = 4
		elif tag == "Unit Exponent":    tag = 5
		elif tag == "Unit":             tag = 6
		elif tag == "Report Size":      tag = 7
		elif tag == "Report ID":        tag = 8
		elif tag == "Report Count":     tag = 9
		elif tag == "Push":             tag = 10
		elif tag == "Pop":              tag = 11
		else: raise Exception("Unknown type {} for {} tag".format(tag, typ))
		typ = 1
	elif typ == "Local":
		if   tag == "Usage":              tag = 0
		elif tag == "Usage Minimum":      tag = 1
		elif tag == "Usage Maximum":      tag = 2
		#elif tag == "Designator Index":   tag = 3
		#elif tag == "Designator Minimum": tag = 4
		#elif tag == "Designator Maximum": tag = 5
		#elif tag == "String Index":       tag = 7
		#elif tag == "String Minimum":     tag = 8
		#elif tag == "String Maximum":     tag = 9
		#elif tag == "Delimeter":          tag = 10
		else: raise Exception("Unknown type {} for {} tag".format(tag, typ))
		typ = 2
	else:
		raise Exception("Unknown item type {}".format(typ))
	
	#TODO: Handle long items; See HID 1.11 spec, pages 26-27
	n = len(data)
	if n == 4:
		n = 3
	result = [(tag & 0xF) << 4 | (typ & 0x3) << 2 | (n & 0x3)]
	result.extend(data)
	return result

def flag_value(value, a, b, n):
	if   value == a: return 0
	elif value == b: return 1 << n
	else: raise Exception("Expected '{}' or '{}', not '{}'".format(a, b, value))

def get_definition(line):
	flags = line.split(" ")
	if len(flags) != 9:
		raise Exception ("Expected to extract 8 flags from '{}'".format(line))
	definition = 0
	definition |= flag_value(flags[0], "Data", "Constant", 0)
	definition |= flag_value(flags[1], "Array", "Variable", 1)
	definition |= flag_value(flags[2], "Absolute", "Relative", 2)
	definition |= flag_value(flags[3], "No_Wrap", "Wrap", 3)
	definition |= flag_value(flags[4], "Linear", "Non_Linear", 4)
	definition |= flag_value(flags[5], "Preferred_State", "No_Preferred", 5)
	definition |= flag_value(flags[6], "No_Null_Position", "Null_State", 6)
	definition |= flag_value(flags[7], "Volatile", "Non_Volatile", 7)
	definition |= flag_value(flags[8], "Bitfield", "Buffered", 8)
	return definition

def read_item(stream):
	for line in stream:
		match = re.search(r"Item\((\w+) *\): (.+), data=(.+)", line)
		if not match:
			raise Exception("Unexpected input '{}'".format(line))
		typ, tag, data = match.groups()
		data = [int(x,16) for x in re.findall(r"0x..", data)]
		
		definition = None
		if is_definition_expected(typ, tag):
			definition = stream.next().strip() + " " + stream.next().strip()
			definition = get_definition(definition)
		elif is_note_expected(typ, tag):
			stream.next()
		
		# For some reason definition isn't required?!?
		item = get_item(typ, tag, data)
		yield struct.pack('B'*len(item), *item)

if __name__=="__main__":
	hexdump = ""
	for item in read_item(sys.stdin):
		hexdump += item
	sys.stdout.write(hexdump)

