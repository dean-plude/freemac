/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A reader for compiled Mac asset catalogues (an app's Resources/Assets.car,
 * freemac 1.271), plain C so it can be tested outside AppKit. NSAssets.m
 * uses it for +[NSImage imageNamed:], +[NSColor colorNamed:] and NSDataAsset
 * when an app carries the Mac's compiled catalogue rather than Ferry's own.
 */
#ifndef AASSETCAR_H
#define AASSETCAR_H
#include <stddef.h>
#include <stdint.h>

struct acar;

/* One picture in a catalogue: 8-bit RGBA, premultiplied, rows of width*4
 * bytes, top row first. scale is 1 for 1x, 2 for @2x and so on. */
struct acar_bitmap {
    int width, height, scale;
    uint8_t *rgba;
};

struct acar *acar_open(const char *path);
void acar_close(struct acar *car);

/* The pictures an image set holds, in the light appearance (or the dark one
 * when that is all it has), one per size and scale. Returns how many were
 * written to out; the caller frees each rgba. */
int acar_image(struct acar *car, const char *name, struct acar_bitmap *out, int max);

/* An image set kept as a drawing (PDF or SVG): its bytes, which the caller
 * frees, or NULL. */
uint8_t *acar_vector(struct acar *car, const char *name, size_t *length);

/* A colour set's colour: components (1 grey or 3 red, green, blue) plus
 * alpha in rgba[0...3]. Returns 0 if there is none. */
int acar_color(struct acar *car, const char *name, double rgba[4]);

/* A data set's bytes, which the caller frees, and its type identifier. */
uint8_t *acar_data(struct acar *car, const char *name, size_t *length, char *uti, size_t uti_size);

#endif
