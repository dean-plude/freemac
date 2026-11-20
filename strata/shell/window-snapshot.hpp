// SPDX-License-Identifier: GPL-3.0-or-later
// strata/snapshot {id, path, size}: draw a window, its frame included, into a
// small PNG no wider or taller than size. Pier shows it in the Dock while the
// window is minimized, as a picture of the window rather than of its app.
// Original freemac code.
#pragma once

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>
#include <cairo.h>
#include <wayfire/opengl.hpp>
#include <wayfire/util/log.hpp>
#include <wayfire/output.hpp>
#include <wayfire/view.hpp>

namespace strata_snapshot
{
/* Returns an empty string on success, else why it failed. */
inline std::string save(wayfire_view view, const std::string& path, int max_size,
    int& out_width, int& out_height)
{
    auto root = view->get_surface_root_node();
    wf::geometry_t box = root->get_bounding_box();
    if ((box.width <= 0) || (box.height <= 0))
    {
        return "the window has no size";
    }

    /* Wayfire's own snapshot, at the window's full size; it is made smaller
     * below, with cairo's smooth scaling. */
    wf::render_target_t target;
    view->take_snapshot(target);
    int full_width  = target.viewport_width;
    int full_height = target.viewport_height;
    if ((full_width <= 0) || (full_height <= 0))
    {
        return "the window couldn't be drawn";
    }

    float scale = std::min(1.0f, 1.0f * max_size / std::max(full_width, full_height));
    int width   = std::max(1, (int)std::lround(full_width * scale));
    int height  = std::max(1, (int)std::lround(full_height * scale));

    std::vector<uint8_t> rgba((size_t)full_width * full_height * 4);
    /* Bind the snapshot's own framebuffer for reading; render_begin(target)
     * leaves a draw binding the driver reports as incomplete for reads. */
    OpenGL::render_begin();
    GL_CALL(glBindFramebuffer(GL_FRAMEBUFFER, target.fb));
    GL_CALL(glViewport(0, 0, full_width, full_height));
    GL_CALL(glPixelStorei(GL_PACK_ALIGNMENT, 1));
    GL_CALL(glReadPixels(0, 0, full_width, full_height, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data()));
    if (getenv("STRATA_SNAPSHOT_DEBUG"))
    {
        LOGI("strata snapshot fb=", target.fb, " tex=", target.tex, " ", full_width, "x", full_height,
            " status=", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }

    target.release();
    OpenGL::render_end();

    /* GL's rows run bottom to top, in RGBA; cairo wants top to bottom, in
     * native-endian ARGB. Both are premultiplied. */
    cairo_surface_t *image = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, full_width, full_height);
    if (cairo_surface_status(image) != CAIRO_STATUS_SUCCESS)
    {
        cairo_surface_destroy(image);
        return "out of memory";
    }

    cairo_surface_flush(image);
    uint8_t *data = cairo_image_surface_get_data(image);
    int stride    = cairo_image_surface_get_stride(image);
    for (int y = 0; y < full_height; y++)
    {
        const uint8_t *from = rgba.data() + (size_t)(full_height - 1 - y) * full_width * 4;
        uint32_t *to = (uint32_t*)(data + (size_t)y * stride);
        for (int x = 0; x < full_width; x++)
        {
            const uint8_t *p = from + x * 4;
            to[x] = ((uint32_t)p[3] << 24) | ((uint32_t)p[0] << 16) |
                ((uint32_t)p[1] << 8) | (uint32_t)p[2];
        }
    }

    cairo_surface_mark_dirty(image);
    cairo_surface_t *small = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    cairo_t *cr = cairo_create(small);
    cairo_scale(cr, 1.0 * width / full_width, 1.0 * height / full_height);
    cairo_set_source_surface(cr, image, 0, 0);
    cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
    cairo_paint(cr);
    cairo_destroy(cr);
    cairo_surface_destroy(image);
    cairo_status_t written = cairo_surface_write_to_png(small, path.c_str());
    cairo_surface_destroy(small);
    if (written != CAIRO_STATUS_SUCCESS)
    {
        return "couldn't write the picture";
    }

    out_width  = width;
    out_height = height;
    return "";
}
}
