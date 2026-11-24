#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the test app's nib files, NibApp.app/Contents/Resources/
# Base.lproj/MainMenu.nib (a single file) and Panel.nib/keyedobjects.nib
# (the folder form), as keyed archives laid out the way compiled Mac nibs
# are described publicly: an NSIBObjectData under "IB.objectdata" with
# NSCustomObject, NSWindowTemplate, NSCustomView and NSClassSwapper
# stand-ins and outlet and action connectors. They are made here with
# Python's plistlib, not by Ferry and not by Apple's tools; nib.m loads
# them. PanelArchive.nib holds the panel nib again in the "NIBArchive"
# form that current versions of Xcode write (see ferry/appkit/
# ANibArchive.m), converted from the keyed archive here. dot.png is the
# image the panel's image view names. Tables.nib holds a view-based
# table and an outline view. Bindings.nib holds controls bound to an object
# controller and the shared user defaults controller. DocApp.app holds a document-based app's main
# nib, its document's window nib and an Info.plist with document types,
# for documents.m. Run this again only to change the fixtures.
import os, plistlib, struct
from plistlib import UID


def varint(n):
    """Seven bits a byte, lowest first; the last byte has its top bit set."""
    out = bytearray()
    while True:
        b = n & 0x7f
        n >>= 7
        if not n:
            out.append(b | 0x80)
            return bytes(out)
        out.append(b)


def nib_archive(objects, top):
    """The NIBArchive form of a keyed archive's objects."""
    nib = [("NSObject", [])]          # (class, [(key, type, data)]); object 0 is the top
    index = {}                        # keyed-archive UID -> NIBArchive object

    def new(cls):
        nib.append((cls, []))
        return len(nib) - 1

    def string(text):
        i = new("NSString")
        nib[i][1].append(("NS.bytes", 8, text.encode()))
        return i

    for uid, o in enumerate(objects):
        if isinstance(o, dict) and "$class" in o:
            index[uid] = new(objects[o["$class"].data]["$classname"])
        elif isinstance(o, str) and uid:
            index[uid] = string(o)
        elif isinstance(o, (int, float)):
            index[uid] = new("NSNumber")

    def value(key, v):
        if isinstance(v, UID):
            return (key, 9, None) if v.data == 0 else (key, 10, index[v.data])
        if isinstance(v, bool):
            return (key, 5 if v else 4, None)
        if isinstance(v, int):
            for t, fmt in ((0, "<b"), (1, "<h"), (2, "<i"), (3, "<q")):
                try:
                    return (key, t, struct.pack(fmt, v))
                except struct.error:
                    pass
        if isinstance(v, float):
            return (key, 7, struct.pack("<d", v))
        if isinstance(v, bytes):
            return (key, 8, v)
        if isinstance(v, str):
            return (key, 10, string(v))
        raise ValueError("can't write %r" % (v,))

    def fill(i, d):
        cls = nib[i][0]
        values = nib[i][1]
        if cls.endswith(("Array", "Set", "Dictionary")):
            values.append(("NSInlinedValue", 5, None))
            items = d.get("NS.objects", [])
            if cls.endswith("Dictionary"):
                items = [x for pair in zip(d.get("NS.keys", []), items) for x in pair]
            values.extend(value("UINibEncoderEmptyKey", v) for v in items)
            return
        for k in sorted(d):
            if k != "$class":
                values.append(value(k, d[k]))

    fill(0, top)
    for uid, o in enumerate(objects):
        if uid in index and isinstance(o, dict):
            fill(index[uid], o)
        elif uid in index and isinstance(o, (int, float)):
            nib[index[uid]][1].append(value("NS.dblval" if isinstance(o, float) else "NS.intval", o))

    keys, classes = [], []
    for cls, values in nib:
        if cls not in classes:
            classes.append(cls)
        for k, _, _ in values:
            if k not in keys:
                keys.append(k)
    objs, vals, first = b"", b"", 0
    for cls, values in nib:
        objs += varint(classes.index(cls)) + varint(first) + varint(len(values))
        first += len(values)
        for k, t, data in values:
            vals += varint(keys.index(k)) + bytes([t])
            if t == 8:
                vals += varint(len(data)) + data
            elif t == 10:
                vals += struct.pack("<I", data)
            elif data is not None:
                vals += data
    keytab = b"".join(varint(len(k.encode())) + k.encode() for k in keys)
    clstab = b"".join(varint(len(c) + 1) + varint(0) + c.encode() + b"\0" for c in classes)
    header_size = 10 + 40
    tables = [(len(nib), objs), (len(keys), keytab), (first, vals), (len(classes), clstab)]
    header, body, offset = [1, 10], b"", header_size
    for count, data in tables:
        header += [count, offset]
        body += data
        offset += len(data)
    return b"NIBArchive" + struct.pack("<10i", *header) + body


class Archive:
    def __init__(self):
        self.objects = ["$null"]
        self.classes = {}

    def add(self, obj):
        self.objects.append(obj)
        return UID(len(self.objects) - 1)

    def reserve(self):
        self.objects.append(None)
        return UID(len(self.objects) - 1)

    def fill(self, uid, obj):
        self.objects[uid.data] = obj

    def cls(self, name, *supers):
        if name not in self.classes:
            self.classes[name] = self.add({"$classname": name, "$classes": [name, *supers, "NSObject"]})
        return self.classes[name]

    def obj(self, cls, supers, **keys):
        d = {"$class": self.cls(cls, *supers)}
        d.update(keys)
        return d

    def array(self, items, mutable=True):
        name = "NSMutableArray" if mutable else "NSArray"
        supers = ("NSArray",) if mutable else ()
        return self.add(self.obj(name, supers, **{"NS.objects": list(items)}))

    def set(self, items):
        return self.add(self.obj("NSMutableSet", ("NSSet",), **{"NS.objects": list(items)}))

    def data(self, top):
        data = {"$archiver": "NSKeyedArchiver", "$version": 100000, "$top": top, "$objects": self.objects}
        return plistlib.dumps(data, fmt=plistlib.FMT_BINARY, sort_keys=True)

    def save(self, path, top):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(self.data(top))

    def save_nib_archive(self, path, top):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(nib_archive(self.objects, top))


VIEW = ("NSView", "NSResponder")
CONTROL = ("NSControl",) + VIEW
CELL = ("NSActionCell", "NSCell")
CMD = 1 << 20


def custom(a, name):
    return a.add(a.obj("NSCustomObject", (), NSClassName=name))


def font(a, size=13):
    return a.add(a.obj("NSFont", (), NSName=".AppleSystemUIFont", NSSize=float(size), NSfFlags=1044))


def catalog_color(a, name, white):
    fallback = a.add(a.obj("NSColor", (), NSColorSpace=3, NSWhite=b"%g\x00" % white))
    return a.add(a.obj("NSColor", (), NSColorSpace=6, NSCatalogName="System", NSColorName=name, NSColor=fallback))


def text_cell(a, cls, contents, flags, flags2=0, placeholder=None, background=True):
    keys = dict(NSContents=a.add(contents), NSCellFlags=flags, NSCellFlags2=flags2, NSSupport=font(a),
                NSDrawsBackground=background,
                NSBackgroundColor=catalog_color(a, "textBackgroundColor", 1),
                NSTextColor=catalog_color(a, "controlTextColor", 0))
    if placeholder:
        keys["NSPlaceholderString"] = a.add(placeholder)
    supers = ("NSTextFieldCell",) + CELL if cls != "NSTextFieldCell" else CELL
    return a.add(a.obj(cls, supers, **keys))


def button_cell(a, title, key="", flags2=1, image=None, flags=0x04000000 | 0x00800000):
    keys = dict(NSContents=a.add(title), NSCellFlags=0x04000000, NSCellFlags2=0x08000000, NSSupport=font(a),
                NSButtonFlags=flags, NSButtonFlags2=flags2, NSKeyEquivalent=a.add(key),
                NSAlternateContents=a.add(""), NSPeriodicDelay=400, NSPeriodicInterval=75)
    if image:
        keys["NSAlternateImage"] = a.add(a.obj("NSButtonImageSource", (), NSImageName=a.add(image)))
    return a.add(a.obj("NSButtonCell", CELL, **keys))


def view(a, uid, cls, supers, frame, vflags, superview, **keys):
    keys.update(NSFrame=frame, NSvFlags=vflags, NSSuperview=superview)
    a.fill(uid, a.obj(cls, supers, **keys))


def connector(a, kind, src, dst, label):
    return a.add(a.obj(kind, ("NSNibConnector",), NSSource=src, NSDestination=dst, NSLabel=a.add(label)))


def object_data(a, root, pairs, connections, visible, names):
    keys = [o for o, _ in pairs]
    parents = [p for _, p in pairs]
    return a.add(a.obj("NSIBObjectData", (),
                       NSRoot=root,
                       NSObjectsKeys=a.array(keys), NSObjectsValues=a.array(parents),
                       NSOidsKeys=a.array(keys), NSOidsValues=a.array([a.add(i + 1) for i in range(len(keys))]),
                       NSNamesKeys=a.array([o for o, _ in names]), NSNamesValues=a.array([a.add(n) for _, n in names]),
                       NSConnections=a.array(connections), NSVisibleWindows=a.set(visible),
                       NSNextOid=len(keys) + 1, NSFramework=a.add("IBCocoaFramework")))


def main_menu_nib(path):
    a = Archive()
    owner = custom(a, "NSApplication")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    delegate = custom(a, "AppDelegate")

    # Menus: the application menu (Say Hello, a separator, Quit) and a Window menu.
    menu, appmenu, winmenu = a.reserve(), a.reserve(), a.reserve()
    appitem, winitem, hello, sep, quit_, minimize = (a.reserve() for _ in range(6))
    def item(uid, parent, title, key="", mask=CMD, **extra):
        a.fill(uid, a.obj("NSMenuItem", (), NSMenu=parent, NSTitle=a.add(title), NSKeyEquiv=a.add(key),
                          NSKeyEquivModMask=mask, NSMnemonicLoc=0x7fffffff, **extra))
    item(appitem, menu, "NibApp", NSSubmenu=appmenu, NSAction=a.add("submenuAction:"))
    item(winitem, menu, "Window", NSSubmenu=winmenu, NSAction=a.add("submenuAction:"))
    item(hello, appmenu, "Say Hello", "h")
    item(sep, appmenu, "", mask=0, NSIsSeparator=True, NSIsDisabled=True)
    item(quit_, appmenu, "Quit NibApp", "q")
    item(minimize, winmenu, "Minimize", "m")
    a.fill(menu, a.obj("NSMenu", (), NSTitle=a.add("AMainMenu"), NSMenuItems=a.array([appitem, winitem]),
                       NSName=a.add("_NSMainMenu")))
    a.fill(appmenu, a.obj("NSMenu", (), NSTitle=a.add("NibApp"), NSMenuItems=a.array([hello, sep, quit_]),
                          NSName=a.add("_NSAppleMenu")))
    a.fill(winmenu, a.obj("NSMenu", (), NSTitle=a.add("Window"), NSMenuItems=a.array([minimize]),
                          NSName=a.add("_NSWindowsMenu")))

    # The window and its views.
    content = a.reserve()
    field, secure, greet, loud, swatch, swapped, label, unknown = (a.reserve() for _ in range(8))
    window = a.add(a.obj("NSWindowTemplate", (),
                         NSWindowStyleMask=15, NSWindowBacking=2, NSWindowRect="{{196, 240}, {480, 270}}",
                         NSWTFlags=0x78000000, NSWindowTitle=a.add("Nib Window"), NSWindowClass=a.add("NSWindow"),
                         NSViewClass=UID(0), NSWindowView=content, NSScreenRect="{{0, 0}, {1440, 900}}",
                         NSMaxSize="{10000000000000, 10000000000000}", NSMinSize="{300, 200}",
                         NSFrameAutosaveName=a.add("")))
    view(a, content, "NSView", VIEW, "{{0, 0}, {480, 270}}", 256 | 18, UID(0),
         NSSubviews=a.array([field, secure, greet, loud, swatch, swapped, label, unknown]), NSNextKeyView=field)
    editable = 0x10000000 | 0x00200000 | 0x00400000 | 0x00100000 | 0x04000000
    view(a, field, "NSTextField", CONTROL, "{{20, 228}, {440, 22}}", 256 | 2 | 8, content,
         NSCell=text_cell(a, "NSTextFieldCell", "Ada", editable, placeholder="Your name"),
         NSEnabled=True, NSNextKeyView=secure)
    view(a, secure, "NSSecureTextField", ("NSTextField",) + CONTROL, "{{20, 196}, {200, 22}}", 256 | 8, content,
         NSCell=text_cell(a, "NSSecureTextFieldCell", "", editable, placeholder="Password"),
         NSEnabled=True, NSNextKeyView=greet)
    view(a, greet, "NSButton", CONTROL, "{{370, 13}, {96, 32}}", 256 | 1, content,
         NSCell=button_cell(a, "Greet", "\r"), NSEnabled=True, NSNextKeyView=loud)
    view(a, loud, "NSButton", CONTROL, "{{18, 60}, {100, 18}}", 256 | 32, content,
         NSCell=button_cell(a, "Loud", flags2=2, image="NSSwitch", flags=0x04000000), NSEnabled=True)
    view(a, swatch, "NSCustomView", VIEW, "{{20, 90}, {40, 40}}", 256 | 4, content,
         NSClassName=a.add("ColorSwatch"))
    a.fill(swapped, a.obj("NSClassSwapper", (), NSClassName=a.add("LoudButton"),
                          NSOriginalClassName=a.add("NSButton"), NSFrame="{{140, 13}, {120, 32}}", NSvFlags=256,
                          NSSuperview=content, NSCell=button_cell(a, "Swapped"), NSEnabled=False))
    view(a, label, "NSTextField", CONTROL, "{{80, 90}, {140, 50}}", 256, content,
         NSCell=text_cell(a, "NSTextFieldCell", "A label long enough to wrap onto more lines", 0x04000040,
                          background=False), NSEnabled=True)
    view(a, unknown, "NSCustomView", VIEW, "{{300, 90}, {40, 40}}", 256, content, NSClassName=a.add("NoSuchView"))

    # Connections, as Interface Builder makes them.
    out, act = "NSNibOutletConnector", "NSNibControlConnector"
    conns = [
        connector(a, out, app, delegate, "delegate"),
        connector(a, out, delegate, window, "window"),
        connector(a, out, delegate, field, "nameField"),
        connector(a, out, delegate, secure, "secureField"),
        connector(a, out, delegate, greet, "greetButton"),
        connector(a, out, delegate, loud, "loudBox"),
        connector(a, out, delegate, swatch, "swatch"),
        connector(a, out, delegate, swapped, "swapped"),
        connector(a, out, delegate, label, "label"),
        connector(a, out, delegate, unknown, "unknownView"),
        connector(a, act, greet, delegate, "greet:"),
        connector(a, act, loud, delegate, "toggleLoud:"),
        connector(a, act, hello, delegate, "sayHello:"),
        connector(a, act, quit_, first, "terminate:"),
        connector(a, act, minimize, first, "performMiniaturize:"),
        a.add(a.obj("NSIBUserDefinedRuntimeAttributesConnector", ("NSNibConnector",), NSObject=swatch,
                    NSKeyPaths=a.array([a.add("swatchName"), a.add("corner")]),
                    NSValues=a.array([a.add("teal"), a.add(4)]))),
    ]
    pairs = [(owner, owner), (first, owner), (app, owner), (delegate, owner), (menu, owner), (window, owner),
             (appitem, menu), (winitem, menu), (appmenu, appitem), (winmenu, winitem), (hello, appmenu),
             (sep, appmenu), (quit_, appmenu), (minimize, winmenu), (content, window)]
    pairs += [(v, content) for v in (field, secure, greet, loud, swatch, swapped, label, unknown)]
    names = [(owner, "File's Owner"), (first, "First Responder"), (app, "Application"), (menu, "MainMenu")]
    data = object_data(a, owner, pairs, conns, [window], names)
    a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def panel_nib(path, nib_archive_form=False):
    a = Archive()
    owner = custom(a, "PanelController")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    helper = custom(a, "Helper")
    missing = custom(a, "NoSuchHelper")
    content, note, badge = a.reserve(), a.reserve(), a.reserve()
    panel = a.add(a.obj("NSWindowTemplate", (), NSWindowStyleMask=3, NSWindowBacking=2,
                        NSWindowRect="{{100, 100}, {240, 120}}", NSWindowTitle=a.add("A Panel"),
                        NSWindowClass=a.add("NSPanel"), NSWindowView=content))
    view(a, content, "NSView", VIEW, "{{0, 0}, {240, 120}}", 256 | 18, UID(0), NSSubviews=a.array([note, badge]))
    view(a, note, "NSTextField", CONTROL, "{{20, 50}, {200, 20}}", 256, content,
         NSCell=text_cell(a, "NSTextFieldCell", "From the panel nib", 0x04000000, background=False))
    dot = a.add(a.obj("NSCustomResource", (), NSClassName=a.add("NSImage"), NSResourceName=a.add("dot")))
    badge_cell = a.add(a.obj("NSImageCell", ("NSCell",), NSCellFlags=0, NSCellFlags2=0x02000000, NSContents=dot,
                             NSAlign=0, NSScale=3, NSStyle=0, NSAnimates=False))
    view(a, badge, "NSImageView", CONTROL, "{{20, 80}, {16, 16}}", 256, content,
         NSCell=badge_cell, NSEditable=False, NSEnabled=True)
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, panel, "panel"), connector(a, out, owner, note, "note"),
             connector(a, out, owner, helper, "helper"), connector(a, out, helper, owner, "owner"),
             connector(a, out, owner, note, "noSuchOutlet"), connector(a, out, owner, badge, "badge")]
    pairs = [(owner, owner), (first, owner), (app, owner), (helper, owner), (missing, owner), (panel, owner),
             (content, panel), (note, content), (badge, content)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    if nib_archive_form:
        a.save_nib_archive(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})
    else:
        a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def window_controller_nib(path):
    """A window nib owned by a window controller: the window, a label and a
    button that sends press: to the owner."""
    a = Archive()
    owner = custom(a, "MyWindowController")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    content, status, button = a.reserve(), a.reserve(), a.reserve()
    window = a.add(a.obj("NSWindowTemplate", (), NSWindowStyleMask=15, NSWindowBacking=2,
                         NSWindowRect="{{120, 120}, {300, 140}}", NSWindowTitle=a.add("Controlled"),
                         NSWindowClass=a.add("NSWindow"), NSWindowView=content))
    view(a, content, "NSView", VIEW, "{{0, 0}, {300, 140}}", 256 | 18, UID(0), NSSubviews=a.array([status, button]))
    view(a, status, "NSTextField", CONTROL, "{{20, 90}, {260, 20}}", 256, content,
         NSCell=text_cell(a, "NSTextFieldCell", "Not pressed", 0x04000000, background=False))
    view(a, button, "NSButton", CONTROL, "{{20, 30}, {100, 32}}", 256, content,
         NSCell=button_cell(a, "Press"), NSEnabled=True)
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, window, "window"), connector(a, out, owner, status, "status"),
             connector(a, "NSNibControlConnector", button, owner, "press:")]
    pairs = [(owner, owner), (first, owner), (app, owner), (window, owner),
             (content, window), (status, content), (button, content)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def view_controller_nib(path):
    """A view nib owned by a view controller, in the NIBArchive form."""
    a = Archive()
    owner = custom(a, "ListViewController")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    top, label = a.reserve(), a.reserve()
    view(a, top, "NSView", VIEW, "{{0, 0}, {200, 80}}", 256 | 18, UID(0), NSSubviews=a.array([label]))
    view(a, label, "NSTextField", CONTROL, "{{10, 30}, {180, 20}}", 256, top,
         NSCell=text_cell(a, "NSTextFieldCell", "From the view nib", 0x04000000, background=False))
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, top, "view"), connector(a, out, owner, label, "label")]
    pairs = [(owner, owner), (first, owner), (app, owner), (top, owner), (label, top)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    a.save_nib_archive(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def dot_png(path):
    """An 8x8 blue disc on clear, as PNG, drawn here pixel by pixel."""
    import zlib
    rows = b""
    for y in range(8):
        rows += b"\x00"
        for x in range(8):
            inside = (x - 3.5) ** 2 + (y - 3.5) ** 2 <= 16
            rows += bytes((0, 0, 255, 255)) if inside else bytes(4)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def panes_nib(path):
    """A view nib in the NIBArchive form with a split view (two panes side by
    side, an autosave name) and, in the right pane, a tab view of two tabs,
    the second selected: its view is a subview of the tab view, as Xcode
    writes it."""
    a = Archive()
    owner = custom(a, "PanesOwner")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    top, split, left, right, tabs, general, advanced, g_label, a_label = (a.reserve() for _ in range(9))
    view(a, top, "NSView", VIEW, "{{0, 0}, {320, 200}}", 256 | 18, UID(0), NSSubviews=a.array([split]))
    view(a, split, "NSSplitView", VIEW, "{{0, 0}, {320, 200}}", 256 | 18, top, NSSubviews=a.array([left, right]),
         NSIsVertical=True, NSDividerStyle=2, NSAutosaveName=a.add("PanesSplit"))
    view(a, left, "NSView", VIEW, "{{0, 0}, {100, 200}}", 256, split)
    view(a, right, "NSView", VIEW, "{{101, 0}, {219, 200}}", 256 | 18, split, NSSubviews=a.array([tabs]))
    view(a, general, "NSView", VIEW, "{{10, 33}, {199, 154}}", 256 | 18, UID(0), NSSubviews=a.array([g_label]))
    view(a, advanced, "NSView", VIEW, "{{10, 33}, {199, 154}}", 256 | 18, tabs, NSSubviews=a.array([a_label]))
    view(a, g_label, "NSTextField", CONTROL, "{{10, 100}, {180, 20}}", 256, general,
         NSCell=text_cell(a, "NSTextFieldCell", "General settings", 0x04000000, background=False))
    view(a, a_label, "NSTextField", CONTROL, "{{10, 100}, {180, 20}}", 256, advanced,
         NSCell=text_cell(a, "NSTextFieldCell", "Advanced settings", 0x04000000, background=False))
    item_g = a.add(a.obj("NSTabViewItem", (), NSIdentifier=a.add("general"), NSLabel=a.add("General"),
                         NSView=general, NSTabView=tabs))
    item_a = a.add(a.obj("NSTabViewItem", (), NSIdentifier=a.add("advanced"), NSLabel=a.add("Advanced"),
                         NSView=advanced, NSTabView=tabs))
    view(a, tabs, "NSTabView", VIEW, "{{0, 0}, {219, 200}}", 256 | 18, right, NSSubviews=a.array([advanced]),
         NSTabViewItems=a.array([item_g, item_a]), NSSelectedTabViewItem=item_a, NSTvFlags=0,
         NSDrawsBackground=True, NSAllowTruncatedLabels=True, NSFont=font(a))
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, top, "view"), connector(a, out, owner, split, "split"),
             connector(a, out, owner, tabs, "tabs"), connector(a, out, split, owner, "delegate"),
             connector(a, out, tabs, owner, "delegate")]
    pairs = [(owner, owner), (first, owner), (app, owner), (top, owner), (split, top), (left, split),
             (right, split), (tabs, right), (general, tabs), (advanced, tabs), (g_label, general),
             (a_label, advanced)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    a.save_nib_archive(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def cell_view_nib():
    """The bytes of a view-based table's cell view prototype: an
    NSTableCellView named "NameCell" holding a text field, its textField
    outlet connected, as a nib inside the table's nib."""
    a = Archive()
    owner = custom(a, "NSObject")
    first = custom(a, "FirstResponder")
    cell, field = a.reserve(), a.reserve()
    view(a, cell, "NSTableCellView", VIEW, "{{0, 0}, {150, 20}}", 256 | 2, UID(0), NSSubviews=a.array([field]),
         NSIdentifier=a.add("NameCell"))
    view(a, field, "NSTextField", CONTROL, "{{2, 2}, {146, 16}}", 256 | 2, cell,
         NSCell=text_cell(a, "NSTextFieldCell", "Table View Cell", 0x04000000, background=False))
    conns = [connector(a, "NSNibOutletConnector", cell, field, "textField")]
    pairs = [(owner, owner), (first, owner), (cell, owner), (field, cell)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    return a.data({"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def tables_nib(path):
    """A view nib, as a keyed archive, with a view-based table in a scroll
    view (its header in a header clip view, a corner view, two columns
    with sort prototypes, a cell view prototype) and an outline view in a
    second scroll view."""
    a = Archive()
    owner = custom(a, "TablesOwner")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    (top, scroll, clip, header_clip, header, corner, table,
     scroll2, clip2, outline) = (a.reserve() for _ in range(10))
    view(a, top, "NSView", VIEW, "{{0, 0}, {320, 400}}", 256 | 18, UID(0), NSSubviews=a.array([scroll, scroll2]))

    def column(ident, title, width, key, editable=True, hidden=False):
        proto = a.add(a.obj("NSSortDescriptor", (), NSKey=a.add(key), NSAscending=True, NSSelector=a.add("compare:")))
        hcell = text_cell(a, "NSTableHeaderCell", title, 0x04000000, background=False)
        dcell = text_cell(a, "NSTextFieldCell", "Text Cell", 0x04000000, background=False)
        return a.add(a.obj("NSTableColumn", (), NSIdentifier=a.add(ident), NSWidth=float(width), NSMinWidth=40.0,
                           NSMaxWidth=1000.0, NSHeaderCell=hcell, NSDataCell=dcell, NSResizingMask=3,
                           NSIsEditable=editable, NSIsHidden=hidden, NSTableView=table,
                           NSSortDescriptorPrototype=proto))
    name_col = column("name", "Name", 150, "name")
    size_col = column("size", "Size", 120, "size", editable=False)
    prototypes = a.add(a.obj("NSDictionary", (), **{"NS.keys": [a.add("NameCell")],
                                                    "NS.objects": [a.add(a.obj("NSNib", (), NSNibFileData=cell_view_nib()))]}))
    view(a, scroll, "NSScrollView", VIEW, "{{0, 200}, {320, 200}}", 256 | 18, top,
         NSSubviews=a.array([clip, header_clip, corner]), NSContentView=clip, NSHeaderClipView=header_clip,
         NSCornerView=corner, NSsFlags=0x20032, NSAutohidesScrollers=True)
    view(a, clip, "NSClipView", VIEW, "{{1, 29}, {318, 170}}", 256 | 18, scroll, NSSubviews=a.array([table]),
         NSDocView=table, NSDrawsBackground=True)
    view(a, header_clip, "NSClipView", VIEW, "{{1, 1}, {318, 28}}", 256 | 2, scroll, NSSubviews=a.array([header]),
         NSDocView=header, NSDrawsBackground=False)
    view(a, header, "NSTableHeaderView", VIEW, "{{0, 0}, {318, 28}}", 256 | 2, header_clip, NSTableView=table)
    view(a, corner, "_NSCornerView", VIEW, "{{0, 0}, {15, 28}}", 256, scroll)
    tv_flags = 0x40000000 | 0x10000000 | 0x08000000 | 0x00800000  # resizing, empty, multiple, alternating
    view(a, table, "NSTableView", CONTROL, "{{0, 0}, {318, 170}}", 256 | 18, clip,
         NSTableColumns=a.array([name_col, size_col]), NSHeaderView=header, NSCornerView=corner,
         NSRowHeight=20.0, NSIntercellSpacingWidth=3.0, NSIntercellSpacingHeight=2.0, NSTvFlags=tv_flags,
         NSColumnAutoresizingStyle=1, NSGridColor=catalog_color(a, "gridColor", 0.8),
         NSBackgroundColor=catalog_color(a, "controlBackgroundColor", 1), NSDraggingSourceMaskForLocal=15,
         NSDraggingSourceMaskForNonLocal=0, NSAllowsTypeSelect=True, NSEnabled=True,
         NSTableViewArchivedReusableViewsKey=prototypes)
    tree_col = a.add(a.obj("NSTableColumn", (), NSIdentifier=a.add("tree"), NSWidth=200.0, NSMinWidth=40.0,
                           NSMaxWidth=1000.0,
                           NSHeaderCell=text_cell(a, "NSTableHeaderCell", "Tree", 0x04000000, background=False),
                           NSDataCell=text_cell(a, "NSTextFieldCell", "Text Cell", 0x04000000, background=False),
                           NSResizingMask=3, NSIsEditable=True, NSTableView=outline))
    view(a, scroll2, "NSScrollView", VIEW, "{{0, 0}, {320, 190}}", 256 | 18, top, NSSubviews=a.array([clip2]),
         NSContentView=clip2, NSsFlags=0x20032)
    view(a, clip2, "NSClipView", VIEW, "{{1, 1}, {318, 188}}", 256 | 18, scroll2, NSSubviews=a.array([outline]),
         NSDocView=outline)
    view(a, outline, "NSOutlineView", ("NSTableView",) + CONTROL, "{{0, 0}, {318, 188}}", 256 | 18, clip2,
         NSTableColumns=a.array([tree_col]), NSRowHeight=18.0, NSTvFlags=0x40000000 | 0x10000000,
         NSOutlineViewIndentationPerLevelKey=12.0, NSOutlineViewOutlineTableColumnKey=tree_col)
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, top, "view"), connector(a, out, owner, table, "table"),
             connector(a, out, owner, outline, "outline"),
             connector(a, out, table, owner, "dataSource"), connector(a, out, table, owner, "delegate"),
             connector(a, out, outline, owner, "dataSource"), connector(a, out, outline, owner, "delegate")]
    pairs = [(owner, owner), (first, owner), (app, owner), (top, owner), (scroll, top), (clip, scroll),
             (header_clip, scroll), (header, header_clip), (corner, scroll), (table, clip), (scroll2, top),
             (clip2, scroll2), (outline, clip2)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def controls_nib(path):
    """A window nib: a pop-up button (its menu, the second item chosen), a
    segmented control of three segments, a search field that sends only on
    Return, a column stack view of two labels, and a toolbar (its delegate
    File's Owner) with an Open item aimed at File's Owner, a flexible space
    and the standard sidebar item."""
    a = Archive()
    owner = custom(a, "ControlsOwner")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    content, popup, segments, search, stack, one, two = (a.reserve() for _ in range(7))
    menu, small, medium, large = (a.reserve() for _ in range(4))
    toolbar, open_item, flex_item, sidebar_item = (a.reserve() for _ in range(4))
    window = a.add(a.obj("NSWindowTemplate", (), NSWindowStyleMask=15, NSWindowBacking=2,
                         NSWindowRect="{{100, 100}, {400, 220}}", NSWindowTitle=a.add("Controls"),
                         NSWindowClass=a.add("NSWindow"), NSWindowView=content, NSToolbar=toolbar))
    view(a, content, "NSView", VIEW, "{{0, 0}, {400, 220}}", 256 | 18, UID(0),
         NSSubviews=a.array([popup, segments, search, stack]))

    def menu_item(uid, title, tag):
        a.fill(uid, a.obj("NSMenuItem", (), NSMenu=menu, NSTitle=a.add(title), NSKeyEquiv=a.add(""),
                          NSKeyEquivModMask=CMD, NSMnemonicLoc=0x7fffffff, NSTag=tag))
    menu_item(small, "Small", 1)
    menu_item(medium, "Medium", 2)
    menu_item(large, "Large", 3)
    a.fill(menu, a.obj("NSMenu", (), NSTitle=a.add("OtherViews"), NSMenuItems=a.array([small, medium, large])))
    popup_cell = a.add(a.obj("NSPopUpButtonCell", ("NSMenuItemCell", "NSButtonCell") + CELL,
                             NSContents=a.add("Medium"), NSCellFlags=0x04000000, NSCellFlags2=0x08000000,
                             NSSupport=font(a), NSButtonFlags=0x04000000 | 0x00800000, NSButtonFlags2=1,
                             NSKeyEquivalent=a.add(""), NSAlternateContents=a.add(""), NSMenu=menu,
                             NSMenuItem=medium, NSPullDown=False, NSUsesItemFromMenu=True, NSAltersState=True,
                             NSPreferredEdge=1, NSArrowPosition=1))
    view(a, popup, "NSPopUpButton", ("NSButton",) + CONTROL, "{{20, 180}, {120, 25}}", 256, content,
         NSCell=popup_cell, NSEnabled=True)

    def segment(label, selected=False):
        return a.add(a.obj("NSSegmentItem", (), NSSegmentItemLabel=a.add(label), NSSegmentItemSelected=selected,
                           NSSegmentItemWidth=0.0))
    seg_cell = a.add(a.obj("NSSegmentedCell", CELL, NSCellFlags=0x04000000, NSCellFlags2=0, NSSupport=font(a),
                           NSSegmentImages=a.array([segment("Day"), segment("Week", True), segment("Month")]),
                           NSSelectedSegment=1, NSTrackingMode=0, NSSegmentStyle=1))
    view(a, segments, "NSSegmentedControl", CONTROL, "{{160, 180}, {180, 24}}", 256, content,
         NSCell=seg_cell, NSEnabled=True)
    search_cell = a.add(a.obj("NSSearchFieldCell", ("NSTextFieldCell",) + CELL, NSContents=a.add(""),
                              NSCellFlags=0x14000000 | 0x00400000, NSCellFlags2=0, NSSupport=font(a),
                              NSPlaceholderString=a.add("Find a file"), NSDrawsBackground=True,
                              NSBackgroundColor=catalog_color(a, "textBackgroundColor", 1),
                              NSTextColor=catalog_color(a, "controlTextColor", 0),
                              NSMaximumRecents=5, NSSendsWholeSearchString=True))
    view(a, search, "NSSearchField", ("NSTextField",) + CONTROL, "{{20, 140}, {200, 22}}", 256, content,
         NSCell=search_cell, NSEnabled=True)
    view(a, stack, "NSStackView", VIEW, "{{20, 20}, {200, 100}}", 256, content, NSSubviews=a.array([one, two]),
         NSStackViewOrientation=1, NSStackViewAlignment=5, NSStackViewSpacing=4.0, NSStackViewDistribution=0,
         NSStackViewDetachesHiddenViews=True)
    view(a, one, "NSTextField", CONTROL, "{{0, 0}, {60, 17}}", 256, stack,
         NSCell=text_cell(a, "NSTextFieldCell", "First", 0x04000000, background=False))
    view(a, two, "NSTextField", CONTROL, "{{0, 20}, {60, 17}}", 256, stack,
         NSCell=text_cell(a, "NSTextFieldCell", "Second", 0x04000000, background=False))

    a.fill(open_item, a.obj("NSToolbarItem", (), NSToolbarItemIdentifier=a.add("open"),
                            NSToolbarItemLabel=a.add("Open"), NSToolbarItemPaletteLabel=a.add("Open"),
                            NSToolbarItemTarget=owner, NSToolbarItemAction=a.add("openThing:"),
                            NSToolbarItemAutovalidates=True, NSToolbarItemEnabled=True, NSToolbarItemTag=7))
    a.fill(flex_item, a.obj("NSToolbarItem", (), NSToolbarItemIdentifier=a.add("NSToolbarFlexibleSpaceItem")))
    a.fill(sidebar_item, a.obj("NSToolbarItem", (), NSToolbarItemIdentifier=a.add("NSToolbarToggleSidebarItem"),
                               NSToolbarItemLabel=a.add("Sidebar")))
    items = [open_item, flex_item, sidebar_item]
    a.fill(toolbar, a.obj("NSToolbar", (), NSToolbarIdentifier=a.add("ControlsToolbar"), NSToolbarDisplayMode=2,
                          NSToolbarSizeMode=1, NSToolbarPrefersToBeShown=True, NSToolbarShowsBaselineSeparator=True,
                          NSToolbarAllowsUserCustomization=False, NSToolbarAutosavesConfiguration=False,
                          NSToolbarDelegate=owner, NSToolbarIBDefaultItems=a.array(items),
                          NSToolbarIBAllowedItems=a.array(items)))
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, window, "window"), connector(a, out, owner, popup, "popup"),
             connector(a, out, owner, segments, "segments"), connector(a, out, owner, search, "search"),
             connector(a, out, owner, stack, "stack"), connector(a, out, owner, toolbar, "toolbar"),
             connector(a, "NSNibControlConnector", popup, owner, "sizeChosen:")]
    pairs = [(owner, owner), (first, owner), (app, owner), (window, owner), (content, window), (popup, content),
             (menu, popup), (small, menu), (medium, menu), (large, menu), (segments, content), (search, content),
             (stack, content), (one, stack), (two, stack), (toolbar, window), (open_item, toolbar),
             (flex_item, toolbar), (sidebar_item, toolbar)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def more_controls_nib(path):
    """A window nib for more_controls.m: a stepper (0 to 10 by 2, at 4, not
    wrapping), a rating level indicator (3 of 5), a colour well, a date
    picker (date only), a combo box with three items, a path control and a
    token field."""
    a = Archive()
    owner = custom(a, "MoreOwner")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    content, stepper, level, well, picker, combo, path_control, tokens = (a.reserve() for _ in range(8))
    window = a.add(a.obj("NSWindowTemplate", (), NSWindowStyleMask=15, NSWindowBacking=2,
                         NSWindowRect="{{100, 100}, {420, 240}}", NSWindowTitle=a.add("More Controls"),
                         NSWindowClass=a.add("NSWindow"), NSWindowView=content))
    view(a, content, "NSView", VIEW, "{{0, 0}, {420, 240}}", 256 | 18, UID(0),
         NSSubviews=a.array([stepper, level, well, picker, combo, path_control, tokens]))
    stepper_cell = a.add(a.obj("NSStepperCell", CELL, NSCellFlags=0x04000000, NSCellFlags2=0,
                               NSMinValue=0.0, NSMaxValue=10.0, NSIncrement=2.0, NSValue=4.0, NSAutorepeat=True,
                               NSValueWraps=False))
    view(a, stepper, "NSStepper", CONTROL, "{{20, 200}, {19, 27}}", 256, content, NSCell=stepper_cell, NSEnabled=True)
    level_cell = a.add(a.obj("NSLevelIndicatorCell", CELL, NSCellFlags=0x04000000, NSCellFlags2=0,
                             NSIndicatorStyle=3, NSMinValue=0.0, NSMaxValue=5.0, NSValue=3.0, NSWarningValue=0.0,
                             NSCriticalValue=0.0))
    view(a, level, "NSLevelIndicator", CONTROL, "{{60, 204}, {80, 16}}", 256, content, NSCell=level_cell,
         NSEnabled=True)
    rgb = a.add(a.obj("NSColor", (), NSColorSpace=1, NSRGB=b"0.2 0.4 0.6\x00"))
    view(a, well, "NSColorWell", CONTROL, "{{160, 200}, {44, 23}}", 256, content, NSColor=rgb, NSIsBordered=True,
         NSEnabled=True)
    date = a.add(a.obj("NSDate", (), **{"NS.time": 786240000.0}))
    picker_cell = a.add(a.obj("NSDatePickerCell", CELL, NSCellFlags=0x04000000, NSCellFlags2=0, NSSupport=font(a),
                              NSContents=date, NSDatePickerElements=0xe0, NSDatePickerType=0, NSDatePickerMode=0))
    view(a, picker, "NSDatePicker", CONTROL, "{{20, 160}, {120, 27}}", 256, content, NSCell=picker_cell,
         NSEnabled=True)
    combo_cell = a.add(a.obj("NSComboBoxCell", ("NSTextFieldCell",) + CELL, NSContents=a.add(""),
                             NSCellFlags=0x14000000 | 0x00400000, NSCellFlags2=0, NSSupport=font(a),
                             NSDrawsBackground=True, NSBackgroundColor=catalog_color(a, "textBackgroundColor", 1),
                             NSTextColor=catalog_color(a, "controlTextColor", 0),
                             NSPopUpListData=a.array([a.add("Apple"), a.add("Apricot"), a.add("Banana")]),
                             NSCompletes=True, NSVisibleItemCount=3, NSUsesDataSource=False))
    view(a, combo, "NSComboBox", ("NSTextField",) + CONTROL, "{{160, 160}, {140, 22}}", 256, content,
         NSCell=combo_cell, NSEnabled=True)
    url = a.add(a.obj("NSURL", (), **{"NS.base": UID(0), "NS.relative": a.add("file:///usr/share/doc")}))
    path_cell = a.add(a.obj("NSPathCell", CELL, NSCellFlags=0x04000000, NSCellFlags2=0, NSSupport=font(a),
                            NSContents=url, NSPathStyle=0))
    view(a, path_control, "NSPathControl", CONTROL, "{{20, 120}, {380, 22}}", 256, content, NSCell=path_cell,
         NSEnabled=True)
    token_cell = a.add(a.obj("NSTokenFieldCell", ("NSTextFieldCell",) + CELL, NSContents=a.add("red, green"),
                             NSCellFlags=0x14000000 | 0x00400000, NSCellFlags2=0, NSSupport=font(a),
                             NSDrawsBackground=True, NSBackgroundColor=catalog_color(a, "textBackgroundColor", 1),
                             NSTextColor=catalog_color(a, "controlTextColor", 0), NSTokenStyle=2))
    view(a, tokens, "NSTokenField", ("NSTextField",) + CONTROL, "{{20, 80}, {380, 22}}", 256, content,
         NSCell=token_cell, NSEnabled=True)
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, window, "window"), connector(a, out, owner, stepper, "stepper"),
             connector(a, out, owner, level, "level"), connector(a, out, owner, well, "well"),
             connector(a, out, owner, picker, "picker"), connector(a, out, owner, combo, "combo"),
             connector(a, out, owner, path_control, "pathControl"), connector(a, out, owner, tokens, "tokens"),
             connector(a, "NSNibControlConnector", stepper, owner, "stepped:")]
    pairs = [(owner, owner), (first, owner), (app, owner), (window, owner), (content, window), (stepper, content),
             (level, content), (well, content), (picker, content), (combo, content), (path_control, content),
             (tokens, content)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def bindings_nib(path):
    """A window nib with bindings: a text field bound to an object
    controller's selection.name (with a null placeholder), a slider (0 to
    10, eleven tick marks, tick values only) bound to selection.level, and
    a check box bound to the shared user defaults controller's
    values.FerryNibFlag. File's Owner has outlets to each."""
    a = Archive()
    owner = custom(a, "BindingsOwner")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    content, field, slider, check = (a.reserve() for _ in range(4))
    window = a.add(a.obj("NSWindowTemplate", (), NSWindowStyleMask=15, NSWindowBacking=2,
                         NSWindowRect="{{100, 100}, {300, 120}}", NSWindowTitle=a.add("Bindings"),
                         NSWindowClass=a.add("NSWindow"), NSWindowView=content))
    view(a, content, "NSView", VIEW, "{{0, 0}, {300, 120}}", 256 | 18, UID(0),
         NSSubviews=a.array([field, slider, check]))
    view(a, field, "NSTextField", CONTROL, "{{20, 80}, {200, 22}}", 256, content,
         NSCell=text_cell(a, "NSTextFieldCell", "", 0x14000000 | 0x00400000), NSEnabled=True)
    slider_cell = a.add(a.obj("NSSliderCell", CELL, NSContents=a.add(""), NSCellFlags=0x04080000, NSCellFlags2=0,
                              NSSupport=font(a), NSMinValue=0.0, NSMaxValue=10.0, NSValue=3.0, NSAltIncValue=0.0,
                              NSNumberOfTickMarks=11, NSTickMarkPosition=0, NSAllowsTickMarkValuesOnly=True,
                              NSVertical=False))
    view(a, slider, "NSSlider", CONTROL, "{{20, 50}, {200, 27}}", 256, content, NSCell=slider_cell,
         NSEnabled=True)
    view(a, check, "NSButton", CONTROL, "{{20, 20}, {200, 18}}", 256, content,
         NSCell=button_cell(a, "Flag", flags2=2, image="NSSwitch", flags=0x04000000), NSEnabled=True)
    controller = a.add(a.obj("NSObjectController", ("NSController",), NSObjectClassName=a.add("NSMutableDictionary"),
                             NSEditable=True, NSAutomaticallyPreparesContent=False))
    defaults = a.add(a.obj("NSUserDefaultsController", ("NSController",), NSSharedInstance=True))

    def binding(src, dst, name, path, options=None):
        keys = dict(NSSource=src, NSDestination=dst, NSLabel=a.add("%s: %s" % (name, path)),
                    NSBinding=a.add(name), NSKeyPath=a.add(path), NSNibBindingConnectorVersion=2)
        if options:
            keys["NSOptions"] = a.add(a.obj("NSDictionary", (), **{"NS.keys": [a.add(k) for k in options],
                                                                   "NS.objects": [a.add(v) for v in options.values()]}))
        return a.add(a.obj("NSNibBindingConnector", ("NSNibConnector",), **keys))
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, window, "window"), connector(a, out, owner, field, "field"),
             connector(a, out, owner, slider, "slider"), connector(a, out, owner, check, "check"),
             connector(a, out, owner, controller, "controller"),
             binding(field, controller, "value", "selection.name", {"NSNullPlaceholder": "No name"}),
             binding(slider, controller, "value", "selection.level"),
             binding(check, defaults, "value", "values.FerryNibFlag")]
    pairs = [(owner, owner), (first, owner), (app, owner), (window, owner), (content, window), (field, content),
             (slider, content), (check, content), (controller, owner), (defaults, owner)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner"), (controller, "Person Controller"),
                                                    (defaults, "Shared User Defaults Controller")])
    a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def doc_main_menu_nib(path):
    """DocApp's main nib: the application, File and Edit menus a
    document-based app has (Open Recent named _NSRecentDocumentsMenu, as
    Interface Builder names it), the app delegate and the app's own
    NSDocumentController subclass."""
    a = Archive()
    owner = custom(a, "NSApplication")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    delegate = custom(a, "AppDelegate")
    controller = custom(a, "DocController")
    menu, appmenu, filemenu, recentmenu, editmenu = (a.reserve() for _ in range(5))
    appitem, fileitem, edititem, quit_ = (a.reserve() for _ in range(4))
    new, open_, recent, clear, sep, close, save, save_as, revert = (a.reserve() for _ in range(9))
    undo, redo = a.reserve(), a.reserve()

    def item(uid, parent, title, key="", mask=CMD, **extra):
        a.fill(uid, a.obj("NSMenuItem", (), NSMenu=parent, NSTitle=a.add(title), NSKeyEquiv=a.add(key),
                          NSKeyEquivModMask=mask, NSMnemonicLoc=0x7fffffff, **extra))
    sub = a.add("submenuAction:")
    item(appitem, menu, "DocApp", NSSubmenu=appmenu, NSAction=sub)
    item(fileitem, menu, "File", NSSubmenu=filemenu, NSAction=sub)
    item(edititem, menu, "Edit", NSSubmenu=editmenu, NSAction=sub)
    item(quit_, appmenu, "Quit DocApp", "q")
    item(new, filemenu, "New", "n")
    item(open_, filemenu, "Open…", "o")
    item(recent, filemenu, "Open Recent", NSSubmenu=recentmenu, NSAction=sub)
    item(clear, recentmenu, "Clear Menu")
    item(sep, filemenu, "", mask=0, NSIsSeparator=True, NSIsDisabled=True)
    item(close, filemenu, "Close", "w")
    item(save, filemenu, "Save…", "s")
    item(save_as, filemenu, "Save As…", "S", mask=CMD | (1 << 17))
    item(revert, filemenu, "Revert to Saved")
    item(undo, editmenu, "Undo", "z")
    item(redo, editmenu, "Redo", "Z", mask=CMD | (1 << 17))
    a.fill(menu, a.obj("NSMenu", (), NSTitle=a.add("AMainMenu"), NSMenuItems=a.array([appitem, fileitem, edititem]),
                       NSName=a.add("_NSMainMenu")))
    a.fill(appmenu, a.obj("NSMenu", (), NSTitle=a.add("DocApp"), NSMenuItems=a.array([quit_]),
                          NSName=a.add("_NSAppleMenu")))
    a.fill(filemenu, a.obj("NSMenu", (), NSTitle=a.add("File"),
                           NSMenuItems=a.array([new, open_, recent, sep, close, save, save_as, revert])))
    a.fill(recentmenu, a.obj("NSMenu", (), NSTitle=a.add("Open Recent"), NSMenuItems=a.array([clear]),
                             NSName=a.add("_NSRecentDocumentsMenu")))
    a.fill(editmenu, a.obj("NSMenu", (), NSTitle=a.add("Edit"), NSMenuItems=a.array([undo, redo])))
    out, act = "NSNibOutletConnector", "NSNibControlConnector"
    conns = [connector(a, out, app, delegate, "delegate"),
             connector(a, out, delegate, controller, "documents")]
    for uid, action in ((quit_, "terminate:"), (new, "newDocument:"), (open_, "openDocument:"),
                        (clear, "clearRecentDocuments:"), (close, "performClose:"), (save, "saveDocument:"),
                        (save_as, "saveDocumentAs:"), (revert, "revertDocumentToSaved:"), (undo, "undo:"),
                        (redo, "redo:")):
        conns.append(connector(a, act, uid, first, action))
    pairs = [(owner, owner), (first, owner), (app, owner), (delegate, owner), (controller, owner), (menu, owner),
             (appitem, menu), (fileitem, menu), (edititem, menu), (appmenu, appitem), (filemenu, fileitem),
             (editmenu, edititem), (quit_, appmenu), (recentmenu, recent), (clear, recentmenu), (undo, editmenu),
             (redo, editmenu)]
    pairs += [(i, filemenu) for i in (new, open_, recent, sep, close, save, save_as, revert)]
    names = [(owner, "File's Owner"), (first, "First Responder"), (app, "Application"), (menu, "MainMenu")]
    data = object_data(a, owner, pairs, conns, [], names)
    a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


def document_nib(path):
    """A document's window nib, owned by the document: the window and a
    text field the document fills in."""
    a = Archive()
    owner = custom(a, "NoteDocument")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    content, field = a.reserve(), a.reserve()
    window = a.add(a.obj("NSWindowTemplate", (), NSWindowStyleMask=15, NSWindowBacking=2,
                         NSWindowRect="{{200, 200}, {480, 360}}", NSWindowTitle=a.add("Window"),
                         NSWindowClass=a.add("NSWindow"), NSWindowView=content))
    view(a, content, "NSView", VIEW, "{{0, 0}, {480, 360}}", 256 | 18, UID(0), NSSubviews=a.array([field]))
    editable = 0x10000000 | 0x00200000 | 0x00400000 | 0x00100000 | 0x04000000
    view(a, field, "NSTextField", CONTROL, "{{20, 318}, {440, 22}}", 256 | 2 | 8, content,
         NSCell=text_cell(a, "NSTextFieldCell", "", editable), NSEnabled=True)
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, window, "window"), connector(a, out, owner, field, "textField")]
    pairs = [(owner, owner), (first, owner), (app, owner), (window, owner), (content, window), (field, content)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


here = os.path.dirname(os.path.abspath(__file__))
resources = os.path.join(here, "NibApp.app", "Contents", "Resources")
main_menu_nib(os.path.join(resources, "Base.lproj", "MainMenu.nib"))
panel_nib(os.path.join(resources, "Panel.nib", "keyedobjects.nib"))
panel_nib(os.path.join(resources, "PanelArchive.nib"), nib_archive_form=True)
dot_png(os.path.join(resources, "dot.png"))
window_controller_nib(os.path.join(resources, "Controlled.nib"))
view_controller_nib(os.path.join(resources, "ListViewController.nib"))
panes_nib(os.path.join(here, "Panes.nib"))
tables_nib(os.path.join(here, "Tables.nib"))
controls_nib(os.path.join(here, "Controls.nib"))
more_controls_nib(os.path.join(here, "MoreControls.nib"))
bindings_nib(os.path.join(here, "Bindings.nib"))
info = {"CFBundleExecutable": "NibApp", "CFBundleIdentifier": "org.freemac.ferry.nibapp", "CFBundleName": "NibApp",
        "CFBundlePackageType": "APPL", "NSMainNibFile": "MainMenu", "NSPrincipalClass": "NSApplication"}
with open(os.path.join(here, "NibApp.app", "Contents", "Info.plist"), "wb") as f:
    plistlib.dump(info, f)

# DocApp.app, for documents.m: its nibs and an Info.plist with document types.
docapp = os.path.join(here, "DocApp.app", "Contents")
doc_main_menu_nib(os.path.join(docapp, "Resources", "Base.lproj", "MainMenu.nib"))
document_nib(os.path.join(docapp, "Resources", "Document.nib"))
docinfo = {
    "CFBundleExecutable": "DocApp", "CFBundleIdentifier": "org.freemac.ferry.docapp", "CFBundleName": "DocApp",
    "CFBundlePackageType": "APPL", "NSMainNibFile": "MainMenu", "NSPrincipalClass": "NSApplication",
    "CFBundleDocumentTypes": [
        {"CFBundleTypeName": "Note", "CFBundleTypeRole": "Editor", "LSItemContentTypes": ["org.freemac.ferry.note"],
         "NSDocumentClass": "NoteDocument"},
        {"CFBundleTypeName": "Plain Text", "CFBundleTypeRole": "Viewer", "CFBundleTypeExtensions": ["txt", "text"],
         "NSDocumentClass": "NoteDocument"},
        {"CFBundleTypeName": "Note Bundle", "CFBundleTypeRole": "Editor", "CFBundleTypeExtensions": ["notes"],
         "LSTypeIsPackage": True, "NSDocumentClass": "BundleDocument"},
        {"CFBundleTypeName": "Old Note", "CFBundleTypeRole": "Editor", "CFBundleTypeExtensions": ["onote"],
         "NSDocumentClass": "OldDocument"},
    ],
    "UTExportedTypeDeclarations": [
        {"UTTypeIdentifier": "org.freemac.ferry.note", "UTTypeDescription": "Ferry Note",
         "UTTypeConformsTo": ["public.plain-text"],
         "UTTypeTagSpecification": {"public.filename-extension": ["note"]}},
    ],
}
with open(os.path.join(docapp, "Info.plist"), "wb") as f:
    plistlib.dump(docinfo, f)
