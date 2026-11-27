# Ferry's Metal

Metal.framework for Mac programs under Ferry, written from Apple's public
Metal documentation and the Metal Shading Language specification. Nothing
here comes from Apple's code, headers or frameworks.

It draws in software, on the processor, so a program that draws with Metal
works on any PC, with or without a graphics card. It is slower than a real
GPU, so it suits a program's windows and previews more than games.

## The parts

- **`ferry-mslc`** compiles Metal shader source (what a program passes to
  `newLibraryWithSource:`) to a small native library of x86-64 code, using
  this system's clang (its OpenCL C++ mode) and lld. The headers in `msl/`
  give the shading language's types and functions. A compiled shader is
  kept in `~/.cache/ferry/metal/`, so it is compiled once. When one doesn't
  compile, the error goes to the program as Metal's own, and the source is
  kept in `last-failed.metal` there.
- **`fw/`** is the framework: the device, buffers, textures and samplers,
  shader libraries and functions with their reflection and function
  constants, render and compute pipelines, depth and stencil states,
  command queues and buffers, render, compute and blit encoders, argument
  encoders, and the drawables a `CAMetalLayer` gives out.
- **The renderer** (`fw/MTLRaster.c`) runs vertex functions, clips and
  rasterizes triangles, lines and points in tiles drawn side by side, runs
  fragment functions, then does the depth and stencil tests, blending and
  writes. Kernels run their threadgroups side by side. `fw/MTLFiber.c`
  gives each pixel of a 2x2 quad and each thread of a threadgroup a small
  stack of its own, so derivatives and threadgroup barriers work.

A command buffer's work runs on its queue's own thread when it is
committed; `FERRY_METAL_SYNC=1` runs it inside `commit` instead, which
helps when looking for a bug.

## When it is on

A program gets a Metal device when it links Metal.framework and not
OpenGL.framework: a program that links both (such as OBS Studio, VLC or a
Qt app) gets no device, so it keeps drawing with OpenGL, which is faster
here. In a program that links neither, such as Python, the library asking for
the device decides the same way: Blender's `bpy` module links Metal and not
OpenGL, so it gets one, and its Workbench and EEVEE engines render with it,
EEVEE's shadows included.
`FERRY_METAL=1` turns Metal on for any program, and `FERRY_METAL=0` turns it
off.

## What's missing

- Ray tracing, mesh shaders, tile shaders and indirect command buffers.
- Barycentric coordinates in fragment functions, and BC (DXT) compressed
  textures being sampled (they can be copied).
- Argument buffers inside argument buffers, and resource heaps. An argument
  buffer itself works: a buffer argument whose struct has `[[id(n)]]`
  members gets its encoder from the function, laid out as the shader reads it
  (Blender keeps its samplers in one).
- Texture atomics work on 32-bit int and uint textures (1D, 2D, their
  arrays and 3D), at mip level 0.

Ferry notes each Metal call a program makes that isn't done yet, once, on
its standard error.

## Tests

`metal/tests/run.sh` checks the shader compiler. `tests/metal/draw.m` and
`tests/metal/layer.m`, which `tests/run.sh` runs, draw with Metal and read
back what was drawn.
