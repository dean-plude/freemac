#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the test app's nib files, NibApp.app/Contents/Resources/
# Base.lproj/MainMenu.nib (a single file) and Panel.nib/keyedobjects.nib
# (the folder form), as keyed archives laid out the way compiled Mac nibs
# are described publicly: an NSIBObjectData under "IB.objectdata" with
# NSCustomObject, NSWindowTemplate, NSCustomView and NSClassSwapper
# stand-ins and outlet and action connectors. They are made here with
# Python's plistlib, not by Ferry and not by Apple's tools; nib.m loads
# them. Run this again only to change the fixtures.
import os, plistlib
from plistlib import UID


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

    def save(self, path, top):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = {"$archiver": "NSKeyedArchiver", "$version": 100000, "$top": top, "$objects": self.objects}
        with open(path, "wb") as f:
            plistlib.dump(data, f, fmt=plistlib.FMT_BINARY, sort_keys=True)


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


def panel_nib(path):
    a = Archive()
    owner = custom(a, "PanelController")
    first = custom(a, "FirstResponder")
    app = custom(a, "NSApplication")
    helper = custom(a, "Helper")
    missing = custom(a, "NoSuchHelper")
    content, note = a.reserve(), a.reserve()
    panel = a.add(a.obj("NSWindowTemplate", (), NSWindowStyleMask=3, NSWindowBacking=2,
                        NSWindowRect="{{100, 100}, {240, 120}}", NSWindowTitle=a.add("A Panel"),
                        NSWindowClass=a.add("NSPanel"), NSWindowView=content))
    view(a, content, "NSView", VIEW, "{{0, 0}, {240, 120}}", 256 | 18, UID(0), NSSubviews=a.array([note]))
    view(a, note, "NSTextField", CONTROL, "{{20, 50}, {200, 20}}", 256, content,
         NSCell=text_cell(a, "NSTextFieldCell", "From the panel nib", 0x04000000, background=False))
    out = "NSNibOutletConnector"
    conns = [connector(a, out, owner, panel, "panel"), connector(a, out, owner, note, "note"),
             connector(a, out, owner, helper, "helper"), connector(a, out, helper, owner, "owner"),
             connector(a, out, owner, note, "noSuchOutlet")]
    pairs = [(owner, owner), (first, owner), (app, owner), (helper, owner), (missing, owner), (panel, owner),
             (content, panel), (note, content)]
    data = object_data(a, owner, pairs, conns, [], [(owner, "File's Owner")])
    a.save(path, {"IB.objectdata": data, "IB.systemFontUpdateVersion": 1})


here = os.path.dirname(os.path.abspath(__file__))
resources = os.path.join(here, "NibApp.app", "Contents", "Resources")
main_menu_nib(os.path.join(resources, "Base.lproj", "MainMenu.nib"))
panel_nib(os.path.join(resources, "Panel.nib", "keyedobjects.nib"))
info = {"CFBundleExecutable": "NibApp", "CFBundleIdentifier": "org.freemac.ferry.nibapp", "CFBundleName": "NibApp",
        "CFBundlePackageType": "APPL", "NSMainNibFile": "MainMenu", "NSPrincipalClass": "NSApplication"}
with open(os.path.join(here, "NibApp.app", "Contents", "Info.plist"), "wb") as f:
    plistlib.dump(info, f)
