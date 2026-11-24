#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes collections_nib.m's fixtures, Collections.nib (a keyed archive)
# and CollectionsArchive.nib (the same nib in the "NIBArchive" form), with
# the helpers of make_nibs.py, whose own fixtures this leaves alone. The
# nib holds a view with a collection view of the older kind in it, and an
# item prototype (a PetItem, by a class swapper) with its own view: a text
# field bound to the item's representedObject.name and a button whose
# action goes to File's Owner. The collection view's settings are under
# the keys Ferry reads (see ferry/appkit/NSCollectionView.m), which aren't
# in Apple's documentation. Run this again only to change the fixtures.
import os

here = os.path.dirname(os.path.abspath(__file__))
# make_nibs.py writes its fixtures when it runs, so only its helpers (the
# part before that) are taken from it.
with open(os.path.join(here, "make_nibs.py")) as f:
    source = f.read()
helpers = {}
exec(compile(source.split("\nhere = os.path.dirname")[0], "make_nibs.py", "exec"), helpers)
Archive, UID = helpers["Archive"], helpers["UID"]
custom, view, connector, object_data = helpers["custom"], helpers["view"], helpers["connector"], helpers["object_data"]
text_cell, button_cell = helpers["text_cell"], helpers["button_cell"]
VIEW, CONTROL = helpers["VIEW"], helpers["CONTROL"]


def collections_nib(path, nib_archive_form=False):
    a = Archive()
    owner = custom(a, "CollectionOwner")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    top, collection, item_view, field, button = (a.reserve() for _ in range(5))
    view(a, top, "NSView", VIEW, "{{0, 0}, {240, 140}}", 256 | 18, UID(0), NSSubviews=a.array([collection]))
    background = a.add(a.obj("NSColor", (), NSColorSpace=3, NSWhite=b"0.9\x00"))
    view(a, collection, "NSCollectionView", VIEW, "{{10, 10}, {200, 120}}", 256 | 18, top,
         NSSelectable=True, NSAllowsMultipleSelection=True, NSMaxNumberOfGridColumns=2,
         NSMinGridSize="{80, 40}", NSBackgroundColors=a.array([background]))
    item = a.add(a.obj("NSClassSwapper", (), NSClassName=a.add("PetItem"),
                       NSOriginalClassName=a.add("NSCollectionViewItem")))
    view(a, item_view, "NSView", VIEW, "{{0, 0}, {80, 40}}", 256, UID(0), NSSubviews=a.array([field, button]))
    view(a, field, "NSTextField", CONTROL, "{{4, 10}, {50, 20}}", 256, item_view,
         NSCell=text_cell(a, "NSTextFieldCell", "", 0x04000000, background=False), NSEnabled=True)
    view(a, button, "NSButton", CONTROL, "{{56, 10}, {20, 20}}", 256, item_view,
         NSCell=button_cell(a, "Go"), NSEnabled=True)
    binding = a.add(a.obj("NSNibBindingConnector", ("NSNibConnector",), NSSource=field, NSDestination=item,
                          NSLabel=a.add("value: representedObject.name"), NSBinding=a.add("value"),
                          NSKeyPath=a.add("representedObject.name"), NSNibBindingConnectorVersion=2))
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, top, "view"), connector(a, out, owner, collection, "collection"),
             connector(a, out, collection, item, "itemPrototype"), connector(a, out, item, item_view, "view"),
             connector(a, out, item, field, "textField"), connector(a, out, item, field, "label"),
             connector(a, "NSNibControlConnector", button, owner, "petPressed:"), binding]
    pairs = [(owner, owner), (first, owner), (app, owner), (top, owner), (collection, top), (item, owner),
             (item_view, owner), (field, item_view), (button, item_view)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    if nib_archive_form:
        a.save_nib_archive(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})
    else:
        a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


collections_nib(os.path.join(here, "Collections.nib"))
collections_nib(os.path.join(here, "CollectionsArchive.nib"), nib_archive_form=True)
