#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Regenerates every framework's FerryProtocols.m (see gen-protocols.sh).
set -eu
cd "$(dirname "$0")/.."
g=sdk/gen-protocols.sh
$g Foundation > foundation/FerryProtocols.m
$g AppKit AVFoundation UserNotifications PIP Quartz ScriptingBridge > appkit/FerryProtocols.m
$g QuartzCore > quartzcore/FerryProtocols.m
$g Metal > metal/fw/FerryProtocols.m
$g WebKit > webkit/FerryProtocols.m
$g CoreData > coredata/FerryProtocols.m
$g CloudKit > cloudkit/FerryProtocols.m
$g ScreenCaptureKit > screencapturekit/FerryProtocols.m
$g JavaScriptCore > javascriptcore/FerryProtocols.m
