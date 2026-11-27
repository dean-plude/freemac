#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the link stub for a Mac framework that one of Ferry's own framework
# files serves (CoreText, ApplicationServices and ImageIO live in CoreGraphics' file,
# SystemConfiguration, CoreServices, CFNetwork, ServiceManagement, IOKit and
# UniformTypeIdentifiers in Foundation's,
# Cocoa, Quartz, QuickLook, ScriptingBridge, CoreImage, MediaPlayer, CoreMedia, CoreMediaIO,
# VideoToolbox, PIP (a private framework) and AddressBook in AppKit's, AudioToolbox and AudioUnit in CoreAudio's): the calls the
# files export for that framework, under
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
kind=Frameworks
case $framework in
    CoreText) pattern='^_(CT|kCT)' ;;
    ApplicationServices) pattern='^_(CG|kCG|CT|kCT|GetCurrentProcess$|GetFrontProcess$|GetNextProcess$|GetProcess|SameProcess$|SetFrontProcess|ShowHideProcess$|IsProcessVisible$|TransformProcessType$|CopyProcessName$|ProcessInformationCopyDictionary$|LaunchApplication$|KillProcess$|AX|kAX|Gestalt$|LS[A-Z]|FS[A-Z]|AE[A-Z]|UT[A-Z]|kUT|GetIconRefFromFileInfo$|AcquireIconRef$|ReleaseIconRef$|Create(ObjSpecifier|OffsetDescriptor|CompDescriptor|LogicalDescriptor|RangeDescriptor)$|UpTime$|AbsoluteTo(Nanoseconds|Duration)$|(Nanoseconds|Duration)To(Absolute|Nanoseconds|Duration)$|(Add|Sub)(Absolute|Nanoseconds|Duration)(To|From)Absolute$|AbsoluteDeltaTo)' ;;
    ImageIO) pattern='^_(CGImageSource|CGImageDestination|kCGImage)' ;;
    UniformTypeIdentifiers) pattern='^_(OBJC_(METACLASS|CLASS)_\$_UTType$|UTType[A-Z][A-Za-z0-9]*$|UTTagClass)' ;;
    SystemConfiguration) pattern='^_(SC|kSC)' ;;
    CFNetwork) pattern='^_(kCFNetworkProxies|CFNetworkCopySystemProxySettings$|kCFStreamProperty|kCFStreamSSL|kCFStreamSocketSecurityLevel|kCFStreamErrorDomain(SSL|NetDB)$|kCFErrorDomainCFNetwork$|CFStreamCreatePairWithSocket)|^_(kCFNetworkProxies|kCFProxy|CFNetworkCopySystemProxySettings$|CFNetworkCopyProxiesForURL$|CFNetworkExecuteProxyAutoConfigurationURL$|kCFStreamProperty|kCFStreamSSL|kCFStreamSocketSecurityLevel|kCFStreamErrorDomain(SSL|NetDB)$|kCFErrorDomainCFNetwork$|CFStreamCreatePairWithSocket)' ;;
    CoreServices) pattern='^_(Gestalt$|LS[A-Z]|kLSSharedFileList|FS[A-Z]|AE[A-Z]|UT[A-Z]|kUT|GetIconRefFromFileInfo$|AcquireIconRef$|ReleaseIconRef$|Create(ObjSpecifier|OffsetDescriptor|CompDescriptor|LogicalDescriptor|RangeDescriptor)$|UpTime$|AbsoluteTo(Nanoseconds|Duration)$|(Nanoseconds|Duration)To(Absolute|Nanoseconds|Duration)$|(Add|Sub)(Absolute|Nanoseconds|Duration)(To|From)Absolute$|AbsoluteDeltaTo)|^_(Gestalt$|UC(CreateCollator|DisposeCollator|CompareText|GetCollationKey|CompareCollationKeys)$|LocaleRefFromLocaleString$|LS[A-Z]|kLSSharedFileList|FS[A-Z]|AE[A-Z]|UT[A-Z]|kUT|GetIconRefFromFileInfo$|AcquireIconRef$|ReleaseIconRef$|Create(ObjSpecifier|OffsetDescriptor|CompDescriptor|LogicalDescriptor|RangeDescriptor)$|UpTime$|AbsoluteTo(Nanoseconds|Duration)$|(Nanoseconds|Duration)To(Absolute|Nanoseconds|Duration)$|(Add|Sub)(Absolute|Nanoseconds|Duration)(To|From)Absolute$|AbsoluteDeltaTo)' ;;
    ServiceManagement) pattern='^_(OBJC_(METACLASS|CLASS)_\$_SM|SM|kSM)' ;;
    IOKit) pattern='^_(IO[A-Z]|kIO)' ;;
    Cocoa) pattern='.' ;;
    Carbon) pattern='^_(Gestalt$|LS[A-Z]|kLSSharedFileList|FS[A-Z]|AE[A-Z]|UT[A-Z]|kUT|GetIconRefFromFileInfo$|AcquireIconRef$|ReleaseIconRef$|Create(ObjSpecifier|OffsetDescriptor|CompDescriptor|LogicalDescriptor|RangeDescriptor)$|UpTime$|AbsoluteTo(Nanoseconds|Duration)$|(Nanoseconds|Duration)To(Absolute|Nanoseconds|Duration)$|(Add|Sub)(Absolute|Nanoseconds|Duration)(To|From)Absolute$|AbsoluteDeltaTo|SameProcess$|CopyProcessName$|ShowHideProcess$|IsProcessVisible$|LaunchApplication$|KillProcess$|PushSymbolicHotKeyMode|PopSymbolicHotKeyMode|GetSymbolicHotKeyMode|kHISymbolicHotKey|GetCurrentEventKeyModifiers|GetCurrentKeyModifiers|GetKeys$|GetApplicationEventTarget|GetEvent|InstallEventHandler|RemoveEventHandler|RegisterEventHotKey|UnregisterEventHotKey|CallNextEventHandler|NewEventHandlerUPP|DisposeEventHandlerUPP|InvokeEventHandlerUPP|AddEventTypesToHandler|RemoveEventTypesFromHandler|RetainEvent$|ReleaseEvent$|CopySymbolicHotKeys|TIS|UCKeyTranslate|LMGetKbdType|GetMBarHeight|GetCurrentProcess|GetFrontProcess|GetNextProcess|GetProcess|TransformProcessType|SetFrontProcess|ProcessInformationCopyDictionary|GetMacOSStatus|AX|kAX|kTIS)|^_(Gestalt$|UC(CreateCollator|DisposeCollator|CompareText|GetCollationKey|CompareCollationKeys)$|LocaleRefFromLocaleString$|LS[A-Z]|kLSSharedFileList|FS[A-Z]|AE[A-Z]|UT[A-Z]|kUT|GetIconRefFromFileInfo$|AcquireIconRef$|ReleaseIconRef$|Create(ObjSpecifier|OffsetDescriptor|CompDescriptor|LogicalDescriptor|RangeDescriptor)$|UpTime$|AbsoluteTo(Nanoseconds|Duration)$|(Nanoseconds|Duration)To(Absolute|Nanoseconds|Duration)$|(Add|Sub)(Absolute|Nanoseconds|Duration)(To|From)Absolute$|AbsoluteDeltaTo|SameProcess$|CopyProcessName$|ShowHideProcess$|IsProcessVisible$|LaunchApplication$|KillProcess$|PushSymbolicHotKeyMode|PopSymbolicHotKeyMode|GetSymbolicHotKeyMode|kHISymbolicHotKey|GetCurrentEventKeyModifiers|GetCurrentKeyModifiers|GetKeys$|GetApplicationEventTarget|GetEvent|InstallEventHandler|RemoveEventHandler|RegisterEventHotKey|UnregisterEventHotKey|CallNextEventHandler|NewEventHandlerUPP|DisposeEventHandlerUPP|InvokeEventHandlerUPP|AddEventTypesToHandler|RemoveEventTypesFromHandler|RetainEvent$|ReleaseEvent$|CopySymbolicHotKeys|TIS|UCKeyTranslate|LMGetKbdType|GetMBarHeight|GetCurrentProcess|GetFrontProcess|GetNextProcess|GetProcess|TransformProcessType|SetFrontProcess|ProcessInformationCopyDictionary|GetMacOSStatus|AX|kAX|kTIS)' ;;
    AVFoundation) pattern='^_(OBJC_(METACLASS|CLASS)_\$_AV|AVFileType|AVMediaType|AVCapture(Device|Session)[A-Za-z0-9]*(Notification|Key|Type[A-Za-z]*|Preset[A-Za-z0-9]*)$|AVFoundationErrorDomain$)' ;;
    MediaPlayer) pattern='^_(OBJC_(METACLASS|CLASS)_\$_MP|MP)' ;;
    CoreMedia) pattern='^_(CM|kCM)' ;;
    CoreMediaIO) pattern='^_CMIO' ;;
    VideoToolbox) pattern='^_(VT|kVT)' ;;
    PIP) pattern='^_OBJC_(METACLASS|CLASS)_\$_PIPViewController$'; kind=PrivateFrameworks ;;
    AddressBook) pattern='^_(OBJC_(METACLASS|CLASS)_\$_AB|kAB)' ;;
    UserNotifications) pattern='^_(OBJC_(METACLASS|CLASS)_\$_UN|UN)' ;;
    QuickLook) pattern='^_(QL|kQL)' ;;
    ScriptingBridge) pattern='^_OBJC_(METACLASS|CLASS)_\$_SB(Object|Application|ElementArray)$' ;;
    CoreImage) pattern='^_(OBJC_(METACLASS|CLASS)_\$_CI[A-Z][A-Za-z]*$|kCI|CI(Detector|Feature)[A-Z])' ;;
    Quartz) pattern='^_(OBJC_(METACLASS|CLASS)_\$_(QL|QC)|QL|kQL|QC)' ;;
    # Core Audio's file serves AudioToolbox (with the audio objects' calls
    # its header brings in, 1.232) and AudioUnit (freemac 1.234)
    AudioToolbox) pattern='^_(AudioObject|AudioHardware|AudioComponent|AudioUnit|AudioOutputUnit|AudioQueue|AudioFormat|AudioConverter|AudioServices|AU(Event|Parameter)?Listener|AUParameterSet)' ;;
    # and Core MIDI, with no devices (freemac 1.263)
    CoreMIDI) pattern='^_(MIDI|kMIDI)' ;;
    AudioUnit) pattern='^_(AudioComponent|AudioUnit|AudioOutputUnit)' ;;
    *) echo "gen-alias-tbd.sh: unknown framework $framework" >&2; exit 2 ;;
esac
{
    echo '--- !tapi-tbd'
    echo 'tbd-version:     4'
    echo 'targets:         [ x86_64-macos ]'
    echo "install-name:    '/System/Library/$kind/$framework.framework/Versions/$version/$framework'"
    echo 'current-version: 1.0.0'
    echo 'exports:'
    echo '  - targets:     [ x86_64-macos ]'
    echo '    symbols:     [ '
    for file in "$@"; do "$nm" -gU "$file"; done | awk '{print $3}' | grep -E "$pattern" | sort -u |
        sed "s/.*/                   '&',/" | sed '$ s/,$/ ]/'
    echo '...'
}
