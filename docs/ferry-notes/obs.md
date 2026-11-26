# OBS Studio under Ferry

Notes from getting OBS Studio 33.0.3's Mac app running under Ferry, for the
release notes when the recipe lands (freemac 1.NEXT, Ferry 0.NEXT).

## How it's built

`ferry/apps/obs.sh [WORK]` fetches OBS Studio at its 33.0.3 commit and what
it uses from their own repositories (Qt 6.11.1's qtbase and qtsvg, x264,
mbedtls 3.6.2, jansson, nlohmann/json, SIMDe, uthash; FFmpeg 8.0.1 through
`apps/ffmpeg.sh`; FreeType from qtbase's own copy) and builds them all with
clang aimed at `x86_64-apple-macos12`, Ferry's headers and ld64.lld. Nothing
of theirs is kept in freemac's repository. The app lands at
`WORK/build/obs/OBS.app`, laid out as OBS's own Xcode build and macdeployqt
lay it out, and runs with `./ferry WORK/build/obs/OBS.app`. Qt's plugins sit
inside the bundle (`Contents/PlugIns`, found through `Resources/qt.conf`), so
nothing needs `QT_PLUGIN_PATH`. Where `zip` is installed the recipe also packs
the app, links kept, as `WORK/build/obs/OBS-33.0.3.zip`, which freemac opens
like any other Mac app's download.

Qt is built twice: once for this system, for its build tools (moc, rcc,
uic), and once for Ferry as frameworks with `@rpath` install names. OBS's
CMake wants Xcode on a Mac; with Ferry it is built by Ninja instead.

Two patches, in `ferry/apps/obs/`, are applied to the checkouts:

- `qtbase.patch`: Qt's Cocoa plugin includes and uses its Metal layer
  whatever `FEATURE_metal` says. The patch puts those parts under
  `QT_CONFIG(metal)`, so the plugin builds without Metal. Ferry draws Qt's
  windows through Core Animation layers.
- `obs-studio.patch`: an `OBS_FERRY` option. It takes the macOS CMake path
  without asking for Xcode, Swift or an Apple SDK, and doesn't check OBS's
  prebuilt dependency bundle. It doesn't build libobs-metal. It skips the
  modules named in `OBS_FERRY_SKIP_MODULES`. It also adds two includes
  (`inttypes.h`, `AvailabilityMacros.h`) that a Mac's SDK headers bring in
  by themselves. "Desktop Audio" lists a sound server's monitors, and the
  Text source falls back to a font that is there (see Known gaps). The two
  camera sources (mac-avcapture and its Legacy one) get ARC, which Xcode's
  settings ask for and Ninja doesn't read, and the new one's `@import` lines
  become plain `#import`s, with the frameworks those would link named in its
  CMake, so it builds without clang modules.

Left out: the browser source and docks (CEF), obs-websocket, VST, scripting,
the virtual camera, Syphon, AJA and Decklink cards.
VideoToolbox and Core Audio's AAC encoder are left out too: Ferry has
neither, and FFmpeg's AAC encoder and x264 serve instead.

## What works (on the test machine, with Mesa's llvmpipe)

- The main window, the preview, scenes and sources, the mixer, the docks.
- Screen capture (`screen_capture`, over Ferry's ScreenCaptureKit), once the
  app is allowed to record the screen (`~/.config/freemac/screen-recording.json`,
  set by freemac-allow-control).
- Recording to Matroska with x264 and FFmpeg's AAC, through `obs-ffmpeg-mux`.
  A SIGTERM quits OBS cleanly and the file is finished. (OBS asks before
  quitting while it records unless `ConfirmOnExit=false` in `user.ini`.)
- Sound in recordings, from "macOS Audio Capture" (`sck_audio_capture`,
  desktop sound through ScreenCaptureKit). A 440 Hz tone fed through Ferry's
  null sound device came out at 440 Hz and the same level.
- Recording from a microphone ("Mic/Aux", Core Audio input). OBS asks for
  microphone access once, freemac asks the user, and the answer is kept in
  `~/.config/freemac/microphone.json` (freemac #290). A 440 Hz tone fed to
  Ferry's null device as the input came out at the same pitch.
- Settings (every page), a source's Properties and Filters, and Add Source.
- `--startrecording` and `--collection NAME` on the command line.

## Known gaps

- "Desktop Audio" as OBS sets it up by default (`coreaudio_output_capture`)
  lists only input devices whose UID names a loopback driver (BlackHole,
  Loopback, Soundflower). The patch adds a sound server's monitors of the
  outputs (UIDs ending in `.monitor`) and makes "Default" the monitor of the
  default output. That is written but not yet tried on a real sound server
  (the test machine has only Ferry's null device); "macOS Audio Capture"
  works for desktop sound meanwhile.
- The text source (`text-freetype2`) asks for Helvetica by default, which a
  system without Apple's fonts lacks. Ferry 0.71.0 lists this system's fonts
  in the Mac Fonts folders, and the patch makes the source fall back to Inter,
  Liberation Sans, DejaVu Sans or FreeSans when the face it asks for is
  missing, so a new Text source draws straight away. (Fallback built, not yet
  seen drawing.)
- The camera sources ("Video Capture Device" and its Legacy one) build
  against Ferry 0.81.0, which lists this system's cameras. Headless, they
  load, list Ferry's test camera (`FERRY_CAMERA_TEST=1`), offer its presets
  and open it. In OBS itself, "Video Capture Device" shows the test camera
  in the preview at 1280x720 and records it: a 31 s recording came out as
  1280x720 H.264 at 30 fps with AAC sound, 8 of 965 frames late (software
  GL), saved in ~/Videos. The Legacy source hasn't been tried in OBS yet, and
  no real webcam has. Ferry gives cameras no sound yet, so a camera's own
  microphone isn't captured.
- Frame rate on a machine without a GPU driver: with screen capture under
  Mesa's software renderer (llvmpipe, 4 cores) about a quarter to a third of
  the frames are late. A profile while recording put about three quarters of
  OBS's CPU time in llvmpipe's drawing threads; the screen copy into OBS
  (about 2 %) and the encoder side (about 5 %) are small. So it's software
  OpenGL, and a PC whose GPU has a Mesa driver shouldn't see it. Not yet
  measured on such a PC.
