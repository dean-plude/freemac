# App recipes

Each script here fetches one open-source Mac app and what it uses from
their public repositories, at pinned commits, builds them with Ferry's
SDK and lays out a bundle that `./ferry` runs. Nothing fetched is kept in
freemac's repository; the apps' code stays theirs, under their own
licences. Run a recipe from `ferry/`, after `make`:

    sh apps/RECIPE.sh [WORK]

`WORK` (or `FERRY_APPS_WORK`; `apps/work` by default, which git ignores)
holds the checkouts in `src/` and the builds in `build/APP/`, with the
bundle at `build/APP/APP.app`. A checkout already at its commit isn't
fetched again, so a second run builds offline. `FERRY_APPS_JOBS` sets how
many files compile at once (2 by default).

| Recipe | App | Built with | First ran |
| --- | --- | --- | --- |
| `flycut.sh` | Flycut, a clipboard manager | MJCloudKitUserDefaultsSync | freemac 1.223 |
| `shiftit.sh` | ShiftIt, which moves and sizes windows | Sparkle 1.22.0; the ShortcutRecorder its repository carries | freemac 1.223 |
| `spectacle.sh` | Spectacle, which moves and sizes windows | Sparkle 1.22.0 | freemac 1.223 |
| `keycastr.sh` | KeyCastr, which shows the keys pressed | ShortcutRecorder and Sparkle 2 (its submodules), its plug-ins | freemac 1.224 |
| `macpass.sh` | MacPass, a KeePass password manager | KeePassKit, KissXML, TransformerKit, HNHUi, DDHotKey, Sparkle 2.6.4 | freemac 1.225 |
| `macdown.sh` | MacDown, a Markdown editor | hoedown, LibYAML, handlebars-objc, MASPreferences, PAPreferences, JJPluralForm, M13OrderedDictionary, Prism, Sparkle 1.22.0 | freemac 1.225 |
| `itsycal.sh` | Itsycal, a menu bar calendar | MASShortcut 2.4.0, Sparkle 1.27.1 | freemac 1.232 |
| `tomatobar.sh` | TomatoBar, a SwiftUI menu bar timer | its three Swift packages | freemac 1.230 |
| `vlc.sh` | VLC, the media player (its menus and other windows still to be tried) | VLC 3.0.24 and FFmpeg, from release tarballs checked by checksum | freemac 1.NEXT |

Sequel Pro (freemac 1.226) has no recipe yet: it needs MariaDB
Connector/C built for Ferry, with its hashes over CommonCrypto.

The Objective-C apps are built from their Xcode projects by `xcode.py`,
Ferry's own reader of the project file (`xcode.py list PROJECT` lists its
targets): each target's sources compiled with `sdk/ferry-cc`, its xibs
with `sdk/ferry-ibtool` and its asset catalogues with `sdk/ferry-actool`,
for the Release configuration. `recipe.sh` holds what the recipes share:
`fetch` and `submodule` (a repository, or a submodule at the commit its
parent pins), `xcbuild` (one Xcode target), `embed` (frameworks into an
app), `sparkle1` and `sparkle2` (the updater most of the apps bring), and
for Swift `need_swift`, `swift_lib` and `resource_bundle`.
`sparkle-nodelta.m` stands in for Sparkle 1's binary-delta code, which
needs xar.

The Swift recipe needs a swift.org toolchain (`FERRY_SWIFT_TOOLCHAIN`) and
Ferry's build of Swift's runtime (`swift/build-runtime.sh`); MacDown's
needs bison, flex and a host C compiler.
