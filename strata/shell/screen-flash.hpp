// SPDX-License-Identifier: GPL-3.0-or-later
// Flash the screen when an alert sound occurs, as a Mac can (Dials >
// Accessibility): every display goes briefly white and fades back. The
// alert sound's player asks for it through the IPC method strata/flash, so
// the flash comes with the sound whichever app made it.
// Original freemac code.
#pragma once

#include <algorithm>
#include <map>
#include <memory>
#include <wayfire/core.hpp>
#include <wayfire/opengl.hpp>
#include <wayfire/output.hpp>
#include <wayfire/output-layout.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/util.hpp>

namespace strata_flash
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
uniform mediump float amount;
void main() {
    mediump vec4 colour = texture2D(smp, uvpos);
    gl_FragColor = vec4(mix(colour.rgb, vec3(1.0), amount), 1.0);
}
)";

/* How long the flash takes, in milliseconds: up quickly, then fading. */
static const int LENGTH = 380;
static const double PEAK = 0.62;

class flash_t
{
  public:
    explicit flash_t(wf::output_t *output) : output(output)
    {}

    ~flash_t()
    {
        stop();
    }

    void start(OpenGL::program_t *program)
    {
        this->program = program;
        started = wf::get_current_time();
        if (!running)
        {
            running = true;
            output->render->add_post(&post);
            output->render->add_effect(&pre, wf::OUTPUT_EFFECT_PRE);
        }

        output->render->damage_whole();
    }

    void stop()
    {
        if (running)
        {
            running = false;
            output->render->rem_post(&post);
            output->render->rem_effect(&pre);
            output->render->damage_whole();
        }
    }

  private:
    wf::output_t *output;
    OpenGL::program_t *program = nullptr;
    int64_t started = 0;
    bool running    = false;

    double amount() const
    {
        double t = (wf::get_current_time() - started) / (double)LENGTH;
        if (t < 0.15)
        {
            return PEAK * (t / 0.15);
        }

        return PEAK * std::clamp(1.0 - (t - 0.15) / 0.85, 0.0, 1.0);
    }

    wf::effect_hook_t pre = [=] ()
    {
        if (wf::get_current_time() - started >= LENGTH)
        {
            // Removing the hooks from inside one is safe in Wayfire; the
            // frame after this one draws the screen as it is.
            stop();
            return;
        }

        output->render->damage_whole();
    };

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
        program->uniform1f("amount", running ? (float)amount() : 0.0f);
        GL_CALL(glDisable(GL_BLEND));
        GL_CALL(glDrawArrays(GL_TRIANGLE_FAN, 0, 4));
        GL_CALL(glEnable(GL_BLEND));
        GL_CALL(glBindTexture(GL_TEXTURE_2D, 0));
        program->deactivate();
        OpenGL::render_end();
    };
};

class flashes_t
{
  public:
    void init()
    {
        OpenGL::render_begin();
        program.set_simple(OpenGL::compile_program(vertex_shader, fragment_shader));
        OpenGL::render_end();
        wf::get_core().output_layout->connect(&on_output_removed);
    }

    void fini()
    {
        flashes.clear();
        OpenGL::render_begin();
        program.free_resources();
        OpenGL::render_end();
    }

    /* Flash every display that shows something. */
    void flash()
    {
        for (auto output : wf::get_core().output_layout->get_outputs())
        {
            auto& slot = flashes[output];
            if (!slot)
            {
                slot = std::make_unique<flash_t>(output);
            }

            slot->start(&program);
        }
    }

  private:
    OpenGL::program_t program;
    std::map<wf::output_t*, std::unique_ptr<flash_t>> flashes;

    wf::signal::connection_t<wf::output_removed_signal> on_output_removed =
        [=] (wf::output_removed_signal *ev)
    {
        flashes.erase(ev->output);
    };
};
}
