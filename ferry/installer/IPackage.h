/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Installer: reading Mac installer packages and disk images. Our own
 * code, written from public descriptions of the formats: the xar archive a
 * flat .pkg is (a header, a zlib-compressed XML table of contents and a
 * heap), the Distribution and PackageInfo XML in it, a component's Payload
 * (a gzip, or "pbzx" xz-chunked, cpio archive in the portable odc or newc
 * form), and a disk image, opened with this system's 7-Zip. Nothing from
 * Apple is used. Built with ferry-cc, without ARC. */
#import <Foundation/Foundation.h>

/* ---- a small XML reader: elements, attributes, text ---- */
@interface IXMLNode : NSObject
@property (readonly) NSString *name;
@property (readonly) NSDictionary<NSString *, NSString *> *attributes;
@property (readonly) NSArray<IXMLNode *> *children;
@property (readonly) NSString *text;        /* the text directly inside, trimmed */
+ (IXMLNode *)parse:(NSData *)data;         /* the root element, or nil */
- (IXMLNode *)child:(NSString *)name;
- (NSArray<IXMLNode *> *)all:(NSString *)name;   /* descendants with that name */
- (NSString *)attr:(NSString *)name;
@end

/* One file in a xar archive's table of contents. */
@interface IXarEntry : NSObject
@property (copy) NSString *path, *type, *encoding;
@property unsigned long long offset, length, size;
@end

@interface IXar : NSObject
+ (instancetype)openFile:(NSString *)path error:(NSString **)error;
@property (readonly) NSArray<IXarEntry *> *entries;
- (IXarEntry *)entry:(NSString *)path;
- (NSData *)dataOf:(IXarEntry *)entry;      /* decoded; for small members */
/* Reads a member's raw (still encoded) bytes in pieces. */
- (NSInteger)read:(IXarEntry *)entry at:(unsigned long long)offset into:(void *)buffer length:(size_t)length;
@end

/* Where each installed path goes. Apps (anything inside an X.app folder)
 * go to the Applications folder; everything else under the Ferry root. */
@interface IDestination : NSObject
@property (copy) NSString *applications, *root;
+ (instancetype)standard;   /* ~/Applications and $XDG_DATA_HOME/ferry/root */
- (NSString *)placeFor:(NSString *)installPath app:(NSString **)app;
@end

@interface IComponent : NSObject
@property (copy) NSString *identifier, *version, *member, *installLocation;
@property unsigned long long installKBytes;
@property BOOL hasScripts;
@end

/* A flat package (.pkg), a bundle package, or what a disk image held. */
@interface IPackage : NSObject
+ (instancetype)openPath:(NSString *)path error:(NSString **)error;
/* Called while 7-Zip opens a disk image; returning NO stops it. */
+ (void)setDiskImageWaiter:(BOOL (^)(void))waiter;
@property (readonly, copy) NSString *path, *title;
@property (readonly) NSArray<IComponent *> *components;
@property (readonly) NSAttributedString *welcome, *readme, *license, *conclusion;
@property (readonly) unsigned long long installKBytes;
@property (readonly) BOOL hasScripts, hasChecks;
/* A disk image's apps to copy, when it holds no package. */
@property (readonly) NSArray<NSString *> *apps;
@property (readonly) NSString *imageDirectory;   /* where a disk image was opened, to remove after */
@end

/* Installs a package a piece at a time, so a window stays responsive. */
@interface IInstallJob : NSObject
- (instancetype)initWithPackage:(IPackage *)pkg destination:(IDestination *)dest;
- (BOOL)step;              /* NO when finished (or failed) */
@property (readonly) double fraction;
@property (readonly, copy) NSString *status, *error;
@property (readonly) NSArray<NSString *> *installedApps;
@property (readonly) unsigned long long filesWritten;
@end

/* Opens a disk image into a new folder with 7-Zip; returns nil and an
 * error when it can't. Runs 7-Zip while the block says to wait. */
NSString *IOpenDiskImage(NSString *dmg, NSString **error, BOOL (^keepWaiting)(void));
/* Removes a folder and everything in it. */
void IRemoveTree(NSString *path);
/* Copies an app folder, leaving out the Finder metadata 7-Zip writes next to files. */
BOOL ICopyTree(NSString *from, NSString *to, NSString **error);
NSString *IHumanSize(unsigned long long kbytes);
