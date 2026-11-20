#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes archive.bplist, a keyed archive laid out the way Apple's
# NSKeyedArchiver documents and writes them, but made here with Python's
# plistlib, independently of Ferry's own archiver. archive.m reads it.
# Run it again only to change the fixture; make check uses the saved file.
import os, plistlib
from plistlib import UID

objects = ["$null"]
def add(o):
    objects.append(o)
    return UID(len(objects) - 1)
def cls(name, *supers):
    return add({"$classname": name, "$classes": [name, *supers, "NSObject"]})

c_dict = cls("NSMutableDictionary", "NSDictionary")
c_array = cls("NSArray")
c_marray = cls("NSMutableArray", "NSArray")
c_set = cls("NSSet")
c_date = cls("NSDate")
c_mstring = cls("NSMutableString", "NSString")
c_value = cls("NSValue")
c_attr = cls("NSAttributedString")
c_url = cls("NSURL")
c_point = cls("Point3")
c_missing = cls("MissingPoint", "Point3")

hello = add("hello")
shared = add({"$class": c_point, "x": 1, "y": 2, "z": 3.5, "name": hello})
# An object that refers to itself.
loop = len(objects)
add({"$class": c_point, "x": 7, "y": 8, "z": 0.0, "next": UID(loop)})
missing = add({"$class": c_missing, "x": -4, "y": 5, "z": 6.25})
k = [add("count"), add("pi"), add("yes"), add("list"), add("set"), add("when"), add("bytes"),
     add("mutable"), add("rect"), add("styled"), add("url"), add("same1"), add("same2"),
     add("loop"), add("missing")]
items = add({"$class": c_marray, "NS.objects": [add("one"), add(2), shared]})
s = add({"$class": c_set, "NS.objects": [add("a"), add("b")]})
date = add({"$class": c_date, "NS.time": 86400.0})
data = add(b"\x00\x01\xfe")
mstr = add({"$class": c_mstring, "NS.string": "grow me"})
rect = add({"$class": c_value, "NS.special": 3, "NS.rectval": "{{1, 2}, {30, 40}}"})
bold = add({"$class": c_dict, "NS.keys": [add("weight")], "NS.objects": [add("bold")]})
plain = add({"$class": c_dict, "NS.keys": [], "NS.objects": []})
styled = add({"$class": c_attr, "NSString": add("Hi there"),
              "NSAttributes": add({"$class": c_array, "NS.objects": [bold, plain]}),
              "NSAttributeInfo": add(bytes([2, 0, 6, 1]))})
url = add({"$class": c_url, "NS.base": UID(0), "NS.relative": add("https://example.com/a?b=c")})
values = [add(42), add(3.25), add(True), items, s, date, data, mstr, rect, styled, url, shared, shared,
          UID(loop), missing]
root = add({"$class": c_dict, "NS.keys": k, "NS.objects": values})

archive = {"$archiver": "NSKeyedArchiver", "$version": 100000, "$top": {"root": root}, "$objects": objects}
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "archive.bplist")
with open(out, "wb") as f:
    plistlib.dump(archive, f, fmt=plistlib.FMT_BINARY, sort_keys=True)
