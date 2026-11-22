// SPDX-License-Identifier: GPL-3.0-or-later
// Colour filters, as on a Mac (Dials > Accessibility > Colour filters): the
// whole screen in greys, adjusted for red/green or blue/yellow colour
// blindness, or tinted with a colour, at the strength chosen.
//
// Each display gets a post-processing pass that multiplies every pixel's
// colour by one matrix, worked out here from the filter and its strength
// (strata-shell/colour_filter, colour_filter_intensity,
// colour_filter_tint). With no filter there's no pass at all, so it costs
// nothing when off.
//
// The colour-blindness filters move what can't be told apart into colours
// that can: the screen as that kind of colour blindness sees it is worked
// out with widely published simulation matrices, and what is lost is added
// back to the channels that remain. Original freemac code.
#pragma once

#include <algorithm>
#include <array>
#include <map>
#include <memory>
#include <string>
#include <glm/glm.hpp>
#include <wayfire/core.hpp>
#include <wayfire/opengl.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/output.hpp>
#include <wayfire/output-layout.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/util.hpp>

namespace strata_filters
{
static const char *vertex_shader = R"(
#version 100
attribute mediump vec2 position;
attribute highp vec2 uvPosition;
varying highp vec2 uvpos;
void main() {
    gl_Position = vec4(position.xy, 0.0, 1.0);
    uvpos = uvPosition;
}
)";

static const char *fragment_shader = R"(
#version 100
varying highp vec2 uvpos;
uniform sampler2D smp;
uniform mediump mat4 colour_matrix;
void main() {
    mediump vec4 colour = texture2D(smp, uvpos);
    gl_FragColor = vec4(clamp((colour_matrix * vec4(colour.rgb, 1.0)).rgb, 0.0, 1.0), 1.0);
}
)";

using matrix = std::array<std::array<double, 3>, 3>;

static const matrix IDENTITY = {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}};

static matrix multiply(const matrix& a, const matrix& b)
{
    matrix out{};
    for (int r = 0; r < 3; r++)
    {
        for (int c = 0; c < 3; c++)
        {
            for (int k = 0; k < 3; k++)
            {
                out[r][c] += a[r][k] * b[k][c];
            }
        }
    }

    return out;
}

static matrix add(const matrix& a, const matrix& b, double scale_b = 1.0)
{
    matrix out{};
    for (int r = 0; r < 3; r++)
    {
        for (int c = 0; c < 3; c++)
        {
            out[r][c] = a[r][c] + scale_b * b[r][c];
        }
    }

    return out;
}

/* What's lost to a kind of colour blindness (the colour minus how it's
 * seen), moved into the channels that are seen: colour + shift * lost. */
static matrix corrected(const matrix& seen, const matrix& shift)
{
    matrix lost = add(IDENTITY, seen, -1.0);
    return add(IDENTITY, multiply(shift, lost));
}

/* The filter's matrix at full strength. `tint` is the tint's colour. */
static matrix full_filter(const std::string& name, const std::array<double, 3>& tint)
{
    if (name == "greyscale")
    {
        // Rec. 709 luminance in every channel.
        const std::array<double, 3> y = {0.2126, 0.7152, 0.0722};
        return {{y, y, y}};
    }

    // Red and green confused: red's and green's difference goes to green and blue.
    const matrix red_green_shift = {{{0, 0, 0}, {0.7, 1, 0}, {0.7, 0, 1}}};
    if (name == "protanopia")
    {
        return corrected({{{0.567, 0.433, 0}, {0.558, 0.442, 0}, {0, 0.242, 0.758}}}, red_green_shift);
    }

    if (name == "deuteranopia")
    {
        return corrected({{{0.625, 0.375, 0}, {0.7, 0.3, 0}, {0, 0.3, 0.7}}}, red_green_shift);
    }

    if (name == "tritanopia")
    {
        // Blue and yellow confused: what's lost goes to red and green.
        const matrix blue_yellow_shift = {{{1, 0, 0.7}, {0, 1, 0.7}, {0, 0, 0}}};
        return corrected({{{0.95, 0.05, 0}, {0, 0.433, 0.567}, {0, 0.475, 0.525}}}, blue_yellow_shift);
    }

    if (name == "tint")
    {
        // The screen's brightness, in the tint's colour.
        const std::array<double, 3> y = {0.2126, 0.7152, 0.0722};
        matrix out{};
        for (int r = 0; r < 3; r++)
        {
            for (int c = 0; c < 3; c++)
            {
                out[r][c] = tint[r] * y[c];
            }
        }

        return out;
    }

    return IDENTITY;
}

/* Between no change (0) and the whole filter (1). */
static glm::mat4 filter_matrix(const std::string& name, double strength, const std::array<double, 3>& tint)
{
    strength = std::clamp(strength, 0.0, 1.0);
    matrix m = add(IDENTITY, add(full_filter(name, tint), IDENTITY, -1.0), strength);
    glm::mat4 out(1.0f);
    // glm is column-major: out[column][row].
    for (int r = 0; r < 3; r++)
    {
        for (int c = 0; c < 3; c++)
        {
            out[c][r] = (float)m[r][c];
        }
    }

    return out;
}

class display_filter_t
{
  public:
    display_filter_t(wf::output_t *output, OpenGL::program_t *program, const glm::mat4 *current) :
        output(output), program(program), current(current)
    {
        output->render->add_post(&post);
        output->render->damage_whole();
    }

    ~display_filter_t()
    {
        output->render->rem_post(&post);
        output->render->damage_whole();
    }

    void redraw()
    {
        output->render->damage_whole();
    }

  private:
    wf::output_t *output;
    OpenGL::program_t *program;
    const glm::mat4 *current;

    wf::post_hook_t post = [=] (const wf::framebuffer_t& source, const wf::framebuffer_t& destination)
    {
        static const float vertices[] = {-1.0f, -1.0f, 1.0f, -1.0f, 1.0f, 1.0f, -1.0f, 1.0f};
        static const float coords[]   = {0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f};
        OpenGL::render_begin(destination);
        program->use(wf::TEXTURE_TYPE_RGBA);
        GL_CALL(glBindTexture(GL_TEXTURE_2D, source.tex));
        GL_CALL(glActiveTexture(GL_TEXTURE0));
        program->attrib_pointer("position", 2, 0, vertices);
        program->attrib_pointer("uvPosition", 2, 0, coords);
        program->uniformMatrix4f("colour_matrix", *current);
        GL_CALL(glDisable(GL_BLEND));
        GL_CALL(glDrawArrays(GL_TRIANGLE_FAN, 0, 4));
        GL_CALL(glEnable(GL_BLEND));
        GL_CALL(glBindTexture(GL_TEXTURE_2D, 0));
        program->deactivate();
        OpenGL::render_end();
    };
};

class filters_t
{
  public:
    void init()
    {
        OpenGL::render_begin();
        program.set_simple(OpenGL::compile_program(vertex_shader, fragment_shader));
        OpenGL::render_end();
        auto changed = [=] () { update(); };
        name.set_callback(changed);
        strength.set_callback(changed);
        tint.set_callback(changed);
        wf::get_core().output_layout->connect(&on_output_added);
        wf::get_core().output_layout->connect(&on_output_removed);
        update();
    }

    void fini()
    {
        displays.clear();
        OpenGL::render_begin();
        program.free_resources();
        OpenGL::render_end();
    }

  private:
    wf::option_wrapper_t<std::string> name{"strata-shell/colour_filter"};
    wf::option_wrapper_t<double> strength{"strata-shell/colour_filter_intensity"};
    wf::option_wrapper_t<wf::color_t> tint{"strata-shell/colour_filter_tint"};
    OpenGL::program_t program;
    glm::mat4 current{1.0f};
    std::map<wf::output_t*, std::unique_ptr<display_filter_t>> displays;

    bool active() const
    {
        std::string n = name;
        return n == "greyscale" || n == "protanopia" || n == "deuteranopia" || n == "tritanopia" ||
               n == "tint";
    }

    void update()
    {
        if (!active())
        {
            displays.clear();
            return;
        }

        wf::color_t colour = tint;
        current = filter_matrix(name, strength, {colour.r, colour.g, colour.b});
        for (auto output : wf::get_core().output_layout->get_outputs())
        {
            auto& slot = displays[output];
            if (!slot)
            {
                slot = std::make_unique<display_filter_t>(output, &program, &current);
            } else
            {
                slot->redraw();
            }
        }
    }

    wf::signal::connection_t<wf::output_added_signal> on_output_added =
        [=] (wf::output_added_signal*)
    {
        update();
    };

    wf::signal::connection_t<wf::output_removed_signal> on_output_removed =
        [=] (wf::output_removed_signal *ev)
    {
        displays.erase(ev->output);
    };
};
}
