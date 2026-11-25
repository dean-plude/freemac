#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the link stub for a Mac framework that one of Ferry's own framework
# files serves (CoreText, ApplicationServices and ImageIO live in CoreGraphics' file,
# SystemConfiguration, CoreServices, CFNetwork, ServiceManagement and IOKit in Foundation's,
# Cocoa, Quartz, QuickLook and ScriptingBridge in AppKit's): the calls the files export for that framework, under
# the framework's own Mac install name. A program linked against it records
# the framework as a Mac-built one would, and Ferry's loader serves that name
# from the file. Cocoa, an umbrella, offers everything AppKit, Foundation and
# Core Graphics export, as a Mac's Cocoa re-exports them.
#
#   gen-alias-tbd.sh CoreText frameworks/CoreGraphics.framework/CoreGraphics > CoreText.tbd
#   gen-alias-tbd.sh Cocoa AppKit Foundation CoreGraphics > Cocoa.tbd   (the three framework files)
set -eu
nm=$(command -v llvm-nm 2>/dev/null || ls /usr/lib/llvm-*/bin/llvm-nm 2>/dev/null | head -n 1)
if [ -z "$nm" ]; then
    echo "gen-alias-tbd.sh: llvm-nm (package llvm) isn't installed" >&2
    exit 1
fi
framework=$1
shift
version=A
case $framework in
    CoreText) pattern='^_(CT|kCT)' ;;
    ApplicationServices) pattern='^_(CG|kCG|CT|kCT|GetCurrentProcess$|GetFrontProcess$|GetNextProcess$|GetProcess|SameProcess$|SetFrontProcess|ShowHideProcess$|IsProcessVisible$|TransformProcessType$|CopyProcessName$|ProcessInformationCopyDictionary$|LaunchApplication$|KillProcess$|AX|kAX|Gestalt$|LS[A-Z]|FS[A-Z]|AE[A-Z]|UT[A-Z]|kUT|GetIconRefFromFileInfo$|AcquireIconRef$|ReleaseIconRef$|Create(ObjSpecifier|OffsetDescriptor|CompDescriptor|LogicalDescriptor|RangeDescriptor)$)' ;;
    ImageIO) pattern='^_(CGImageSource|kCGImage)' ;;
    SystemConfiguration) pattern='^_(SC|kSC)' ;;
    CFNetwork) pattern='^_(kCFStreamProperty|kCFStreamSSL|kCFStreamSocketSecurityLevel|kCFStreamErrorDomain(SSL|NetDB)$|kCFErrorDomainCFNetwork$|CFStreamCreatePairWithSocket)' ;;
    CoreServices) pattern='^_(Gestalt$|LS[A-Z]|kLSSharedFileList|FS[A-Z]|AE[A-Z]|UT[A-Z]|kUT|GetIconRefFromFileInfo$|AcquireIconRef$|ReleaseIconRef$|Create(ObjSpecifier|OffsetDescriptor|CompDescriptor|LogicalDescriptor|RangeDescriptor)$)' ;;
    ServiceManagement) pattern='^_(SM|kSM)' ;;
    IOKit) pattern='^_(IO[A-Z]|kIO)' ;;
    Cocoa) pattern='.' ;;
    Carbon) pattern='^_(Gestalt$|LS[A-Z]|kLSSharedFileList|FS[A-Z]|AE[A-Z]|UT[A-Z]|kUT|GetIconRefFromFileInfo$|AcquireIconRef$|ReleaseIconRef$|Create(ObjSpecifier|OffsetDescriptor|CompDescriptor|LogicalDescriptor|RangeDescriptor)$|SameProcess$|CopyProcessName$|ShowHideProcess$|IsProcessVisible$|LaunchApplication$|KillProcess$|PushSymbolicHotKeyMode|PopSymbolicHotKeyMode|GetSymbolicHotKeyMode|kHISymbolicHotKey|GetCurrentEventKeyModifiers|GetCurrentKeyModifiers|GetKeys$|GetApplicationEventTarget|GetEvent|InstallEventHandler|RemoveEventHandler|RegisterEventHotKey|UnregisterEventHotKey|CallNextEventHandler|NewEventHandlerUPP|DisposeEventHandlerUPP|InvokeEventHandlerUPP|AddEventTypesToHandler|RemoveEventTypesFromHandler|RetainEvent$|ReleaseEvent$|CopySymbolicHotKeys|TIS|UCKeyTranslate|LMGetKbdType|GetMBarHeight|GetCurrentProcess|GetFrontProcess|GetNextProcess|GetProcess|TransformProcessType|SetFrontProcess|ProcessInformationCopyDictionary|GetMacOSStatus|AX|kAX|kTIS)' ;;
    UserNotifications) pattern='^_(OBJC_(METACLASS|CLASS)_\$_UN|UN)' ;;
    QuickLook) pattern='^_(QL|kQL)' ;;
    ScriptingBridge) pattern='^_OBJC_(METACLASS|CLASS)_\$_SB(Object|Application|ElementArray)$' ;;
    Quartz) pattern='^_(OBJC_(METACLASS|CLASS)_\$_(QL|QC)|QL|kQL|QC)' ;;
    *) echo "gen-alias-tbd.sh: unknown framework $framework" >&2; exit 2 ;;
esac
{
    echo '--- !tapi-tbd'
    echo 'tbd-version:     4'
    echo 'targets:         [ x86_64-macos ]'
    echo "install-name:    '/System/Library/Frameworks/$framework.framework/Versions/$version/$framework'"
    echo 'current-version: 1.0.0'
    echo 'exports:'
    echo '  - targets:     [ x86_64-macos ]'
    echo '    symbols:     [ '
    for file in "$@"; do "$nm" -gU "$file"; done | awk '{print $3}' | grep -E "$pattern" | sort -u |
        sed "s/.*/                   '&',/" | sed '$ s/,$/ ]/'
    echo '...'
}
