#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes sdk/include/CoreServices/UTCoreTypes.h and foundation/UTCoreTypes.inc
from one table: the constant, the identifier, what it conforms to, its
filename extensions, MIME types and description. The identifiers are the
public ones Apple's "System-Declared Uniform Type Identifiers" lists."""
import os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

T = [
    # constant, identifier, conforms to, extensions, MIME types, description
    ('Item', 'public.item', '', '', '', 'item'),
    ('Content', 'public.content', '', '', '', 'content'),
    ('CompositeContent', 'public.composite-content', 'public.content', '', '', 'composite content'),
    ('Data', 'public.data', 'public.item', '', 'application/octet-stream', 'data'),
    ('Directory', 'public.directory', 'public.item', '', '', 'folder'),
    ('Folder', 'public.folder', 'public.directory', '', '', 'folder'),
    ('Volume', 'public.volume', 'public.folder', '', '', 'volume'),
    ('Package', 'com.apple.package', 'public.directory', '', '', 'package'),
    ('Bundle', 'com.apple.bundle', 'public.directory', 'bundle', '', 'bundle'),
    ('Application', 'com.apple.application', 'public.data', '', '', 'application'),
    ('ApplicationBundle', 'com.apple.application-bundle', 'com.apple.application com.apple.bundle com.apple.package',
     'app', '', 'application'),
    ('ApplicationFile', 'com.apple.application-file', 'com.apple.application public.data', '', '', 'application'),
    ('Framework', 'com.apple.framework', 'com.apple.bundle', 'framework', '', 'framework'),
    ('PluginBundle', 'com.apple.plugin', 'com.apple.bundle com.apple.package', 'plugin', '', 'plug-in'),
    ('SymLink', 'public.symlink', 'public.item', '', '', 'alias'),
    ('AliasFile', 'com.apple.alias-file', 'public.data', '', '', 'alias'),
    ('URL', 'public.url', 'public.data', '', '', 'URL'),
    ('FileURL', 'public.file-url', 'public.url', '', '', 'file URL'),
    ('Text', 'public.text', 'public.data public.content', '', 'text/*', 'text'),
    ('PlainText', 'public.plain-text', 'public.text', 'txt text', 'text/plain', 'plain text document'),
    ('UTF8PlainText', 'public.utf8-plain-text', 'public.plain-text', '', 'text/plain;charset=utf-8',
     'Unicode text'),
    ('UTF16PlainText', 'public.utf16-plain-text', 'public.plain-text', '', '', 'Unicode text'),
    ('RTF', 'public.rtf', 'public.text', 'rtf', 'text/rtf', 'rich text document'),
    ('HTML', 'public.html', 'public.text', 'html htm shtml', 'text/html', 'HTML document'),
    ('XML', 'public.xml', 'public.text', 'xml', 'text/xml application/xml', 'XML document'),
    ('JSON', 'public.json', 'public.text', 'json', 'application/json', 'JSON document'),
    ('CommaSeparatedText', 'public.comma-separated-values-text', 'public.text', 'csv', 'text/csv',
     'comma-separated values'),
    ('TabSeparatedText', 'public.tab-separated-values-text', 'public.text', 'tsv', 'text/tab-separated-values',
     'tab-separated values'),
    ('SourceCode', 'public.source-code', 'public.plain-text', '', '', 'source code'),
    ('CSource', 'public.c-source', 'public.source-code', 'c', 'text/x-c', 'C source'),
    ('ObjectiveCSource', 'public.objective-c-source', 'public.source-code', 'm', '', 'Objective-C source'),
    ('CHeader', 'public.c-header', 'public.source-code', 'h', '', 'C header'),
    ('Script', 'public.script', 'public.source-code', '', '', 'script'),
    ('ShellScript', 'public.shell-script', 'public.script', 'sh command', 'application/x-sh', 'shell script'),
    ('PythonScript', 'public.python-script', 'public.script', 'py', 'text/x-python', 'Python script'),
    ('JavaScript', 'com.netscape.javascript-source', 'public.source-code', 'js', 'text/javascript',
     'JavaScript'),
    ('Log', 'public.log', 'public.plain-text', 'log', '', 'log file'),
    ('Image', 'public.image', 'public.data public.content', '', 'image/*', 'image'),
    ('PNG', 'public.png', 'public.image', 'png', 'image/png', 'PNG image'),
    ('JPEG', 'public.jpeg', 'public.image', 'jpg jpeg jpe', 'image/jpeg', 'JPEG image'),
    ('TIFF', 'public.tiff', 'public.image', 'tiff tif', 'image/tiff', 'TIFF image'),
    ('GIF', 'com.compuserve.gif', 'public.image', 'gif', 'image/gif', 'GIF image'),
    ('BMP', 'com.microsoft.bmp', 'public.image', 'bmp', 'image/bmp', 'Windows bitmap image'),
    ('ICO', 'com.microsoft.ico', 'public.image', 'ico', 'image/x-icon', 'Windows icon image'),
    ('AppleICNS', 'com.apple.icns', 'public.image', 'icns', '', 'Apple icon image'),
    ('ScalableVectorGraphics', 'public.svg-image', 'public.image', 'svg', 'image/svg+xml', 'SVG image'),
    ('PDF', 'com.adobe.pdf', 'public.data public.composite-content', 'pdf', 'application/pdf', 'PDF document'),
    ('RTFD', 'com.apple.rtfd', 'com.apple.package public.composite-content', 'rtfd', '',
     'rich text document with attachments'),
    ('FlatRTFD', 'com.apple.flat-rtfd', 'public.data public.composite-content', '', '',
     'rich text document with attachments'),
    ('WebArchive', 'com.apple.webarchive', 'public.data public.composite-content', 'webarchive', '',
     'web archive'),
    ('PropertyList', 'com.apple.property-list', 'public.data', 'plist', '', 'property list'),
    ('XMLPropertyList', 'com.apple.xml-property-list', 'public.xml com.apple.property-list', '', '',
     'XML property list'),
    ('Archive', 'public.archive', 'public.data', '', '', 'archive'),
    ('ZipArchive', 'com.pkware.zip-archive', 'public.archive', 'zip', 'application/zip', 'ZIP archive'),
    ('GNUZipArchive', 'org.gnu.gnu-zip-archive', 'public.archive', 'gz gzip', 'application/x-gzip',
     'gzip archive'),
    ('Bzip2Archive', 'public.bzip2-archive', 'public.archive', 'bz2', 'application/x-bzip2', 'bzip2 archive'),
    ('DiskImage', 'public.disk-image', 'public.archive', '', '', 'disk image'),
    ('Audiovisual', 'public.audiovisual-content', 'public.data public.content', '', '', 'audiovisual content'),
    ('Movie', 'public.movie', 'public.audiovisual-content', '', 'video/*', 'movie'),
    ('Audio', 'public.audio', 'public.audiovisual-content', '', 'audio/*', 'audio'),
    ('MP3', 'public.mp3', 'public.audio', 'mp3', 'audio/mpeg', 'MP3 audio'),
    ('MPEG4', 'public.mpeg-4', 'public.movie', 'mp4', 'video/mp4', 'MPEG-4 movie'),
    ('QuickTimeMovie', 'com.apple.quicktime-movie', 'public.movie', 'mov qt', 'video/quicktime',
     'QuickTime movie'),
    ('WaveformAudio', 'com.microsoft.waveform-audio', 'public.audio', 'wav wave', 'audio/vnd.wave',
     'waveform audio'),
    ('Font', 'public.font', 'public.data', '', '', 'font'),
    ('TrueTypeFont', 'public.truetype-font', 'public.font', 'ttf', 'font/ttf', 'TrueType font'),
    ('OpenTypeFont', 'public.opentype-font', 'public.font', 'otf', 'font/otf', 'OpenType font'),
    ('Executable', 'public.executable', 'public.item', '', '', 'executable'),
    ('UnixExecutable', 'public.unix-executable', 'public.data public.executable', '', '', 'Unix executable'),
    ('Database', 'public.database', 'public.data', '', '', 'database'),
    ('VCard', 'public.vcard', 'public.text', 'vcf vcard', 'text/vcard', 'vCard'),
    ('Message', 'public.message', 'public.data public.content', '', '', 'message'),
    ('EmailMessage', 'public.email-message', 'public.message', 'eml', 'message/rfc822', 'email message'),
    ('Spreadsheet', 'public.spreadsheet', 'public.content', '', '', 'spreadsheet'),
    ('Presentation', 'public.presentation', 'public.composite-content', '', '', 'presentation'),
    ('X509Certificate', 'public.x509-certificate', 'public.data', 'cer crt der', 'application/x-x509-ca-cert',
     'certificate'),
    ('ElectronicPublication', 'org.idpf.epub-container', 'public.composite-content com.pkware.zip-archive',
     'epub', 'application/epub+zip', 'EPUB book'),
]

h = ['/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */',
     '/* The system\'s uniform type identifiers (freemac 1.223, Ferry 0.47.0), as',
     ' * Apple\'s public list of system-declared types names them. Written by',
     ' * ferry/sdk/gen-uttypes.py, which also writes foundation/UTCoreTypes.inc. */',
     '#ifndef _FERRY_UTCORETYPES_H', '#define _FERRY_UTCORETYPES_H',
     '#include <CoreFoundation/CoreFoundation.h>', '#ifdef __cplusplus', 'extern "C" {', '#endif']
for name, uti, *_ in T:
    h.append('extern const CFStringRef kUTType%s; /* "%s" */' % (name, uti))
h += ['#ifdef __cplusplus', '}', '#endif', '#endif', '']
open('sdk/include/CoreServices/UTCoreTypes.h', 'w').write('\n'.join(h))

c = ['/* Written by ferry/sdk/gen-uttypes.py: the constants and the table of known',
     ' * types for foundation/UTType.m. */']
for name, uti, *_ in T:
    c.append('const CFStringRef kUTType%s = (CFStringRef)@"%s";' % (name, uti))
c.append('static const struct known_type known_types[] = {')
for name, uti, parents, exts, mimes, desc in T:
    c.append('    {"%s", "%s", "%s", "%s", "%s"},' % (uti, parents, exts, mimes, desc))
c.append('};')
c.append('')
open('foundation/UTCoreTypes.inc', 'w').write('\n'.join(c))
