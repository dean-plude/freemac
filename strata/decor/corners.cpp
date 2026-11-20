/*
 * Strata: round the bottom corners of every window.
 *
 * A window's own pixels end in square corners at the bottom. This transformer
 * draws each window through a small shader that rounds those two corners and
 * bends whatever edge or shadow runs along the side and the bottom around the
 * curve, so the corner looks as if the window had always been round there.
 * The top corners are left alone: the title bar (ours or the app's) already
 * rounds them.
 *
 * Original freemac code, GPL-3.0-or-later.
 */
#include <cmath>
#include <memory>

#include <wayfire/core.hpp>
#include <wayfire/opengl.hpp>
#include <wayfire/region.hpp>
#include <wayfire/scene-render.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/toplevel.hpp>
#include <wayfire/view-transform.hpp>

#include "corners.hpp"

namespace strata_corners
{
static const char *NAME = "strata-corners";
static const float RADIUS = 10.0f;  // the same curve as the title bar's top
static const float REACH  = 24.0f;  // how far an edge or shadow is bent round

static const char *vertex_source =
    R"(#version 100
attribute mediump vec2 position;
uniform mat4 MVP;
varying highp vec2 pos;

void main()
{
    gl_Position = MVP * vec4(position.xy, 0.0, 1.0);
    pos = position;
})";

static const char *fragment_source =
    R"(#version 100
@builtin_ext@
@builtin@

varying highp vec2 pos;
uniform highp vec4 bbox;    // what the texture covers: x, y, width, height
uniform highp vec4 rect;    // the window's own area: x, y, width, height
uniform highp float radius; // 0 leaves the window as it is
uniform highp float reach;

highp vec2 to_uv(highp vec2 p)
{
    return vec2((p.x - bbox.x) / bbox.z, 1.0 - (p.y - bbox.y) / bbox.w);
}

mediump vec4 sample_at(highp vec2 p)
{
    if (p.x < bbox.x || p.y < bbox.y || p.x > bbox.x + bbox.z || p.y > bbox.y + bbox.w)
    {
        return vec4(0.0);
    }

    return get_pixel(to_uv(p));
}

void main()
{
    mediump vec4 here = get_pixel(to_uv(pos));
    highp vec2 lo = rect.xy;
    highp vec2 hi = rect.xy + rect.zw;
    bool left  = pos.x < lo.x + radius;
    bool right = pos.x > hi.x - radius;
    if (radius <= 0.0 || pos.y <= hi.y - radius || !(left || right))
    {
        gl_FragColor = here;
        return;
    }

    highp vec2 centre = vec2(left ? lo.x + radius : hi.x - radius, hi.y - radius);
    highp vec2 d = pos - centre;
    highp float dist = length(d);
    highp float k = dist - radius;   // distance outside the curve
    if (k > reach)
    {
        gl_FragColor = here;
        return;
    }

    /* What lies k pixels outside the straight side and the straight bottom,
     * blended by the angle round the corner. */
    highp float side_x = left ? lo.x - max(k, 0.5) : hi.x + max(k, 0.5);
    mediump vec4 side   = sample_at(vec2(side_x, centre.y - 0.5));
    mediump vec4 bottom = sample_at(vec2(centre.x + (left ? 0.5 : -0.5), hi.y + max(k, 0.5)));
    highp float t = atan(max(d.y, 0.0), abs(d.x)) / 1.5707963;
    mediump vec4 edge = mix(side, bottom, clamp(t, 0.0, 1.0));

    highp float inside = clamp(0.5 - k, 0.0, 1.0);
    gl_FragColor = here * inside + edge * (1.0 - inside);
})";

static OpenGL::program_t *program = nullptr;

static void ensure_program()
{
    if (!program)
    {
        program = new OpenGL::program_t();
        program->compile(vertex_source, fragment_source);
    }
}

class corners_node_t : public wf::scene::floating_inner_node_t
{
  public:
    wayfire_toplevel_view view;

    corners_node_t(wayfire_toplevel_view view) : floating_inner_node_t(false), view(view)
    {}

    std::string stringify() const override
    {
        return NAME;
    }

    wf::geometry_t get_bounding_box() override
    {
        return get_children_bounding_box();
    }

    /* The window's own area, without our title bar and edge. */
    wf::geometry_t window_rect()
    {
        auto toplevel = view->toplevel();
        return wf::shrink_geometry_by_margins(view->get_geometry(), toplevel->current().margins);
    }

    float radius()
    {
        auto& state = view->toplevel()->current();
        return state.fullscreen ? 0.0f : RADIUS;
    }

    void gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
        wf::scene::damage_callback push_damage, wf::output_t *shown_on) override;
};

class corners_render_instance_t : public wf::scene::transformer_render_instance_t<corners_node_t>
{
  public:
    using transformer_render_instance_t::transformer_render_instance_t;

    /* A corner is drawn from the pixels beside it, so when anything near the
     * bottom changes, redraw both corners too. */
    void transform_damage_region(wf::region_t& damage) override
    {
        if (damage.empty())
        {
            return;
        }

        auto r    = self->window_rect();
        int reach = (int)std::ceil(RADIUS + REACH);
        damage |= wf::geometry_t{r.x - (int)REACH, r.y + r.height - (int)RADIUS, reach, reach};
        damage |= wf::geometry_t{r.x + r.width - (int)RADIUS, r.y + r.height - (int)RADIUS, reach, reach};
    }

    void render(const wf::render_target_t& target, const wf::region_t& damage) override
    {
        auto bbox = self->get_children_bounding_box();
        auto tex  = get_texture(target.scale);
        auto rect = self->window_rect();

        OpenGL::render_begin(target);
        ensure_program();
        program->use(tex.type);
        program->set_active_texture(tex);

        float x1 = bbox.x, y1 = bbox.y, x2 = bbox.x + bbox.width, y2 = bbox.y + bbox.height;
        GLfloat vertices[] = {x1, y2, x2, y2, x2, y1, x1, y1};
        program->attrib_pointer("position", 2, 0, vertices);
        program->uniformMatrix4f("MVP", target.get_orthographic_projection());
        program->uniform4f("bbox", glm::vec4{bbox.x, bbox.y, bbox.width, bbox.height});
        program->uniform4f("rect", glm::vec4{rect.x, rect.y, rect.width, rect.height});
        program->uniform1f("radius", self->radius());
        program->uniform1f("reach", REACH);

        GL_CALL(glEnable(GL_BLEND));
        GL_CALL(glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA));
        for (const auto& box : damage)
        {
            target.logic_scissor(wlr_box_from_pixman_box(box));
            GL_CALL(glDrawArrays(GL_TRIANGLE_FAN, 0, 4));
        }

        program->deactivate();
        OpenGL::render_end();
    }
};

void corners_node_t::gen_render_instances(std::vector<wf::scene::render_instance_uptr>& instances,
    wf::scene::damage_callback push_damage, wf::output_t *shown_on)
{
    auto instance = std::make_unique<corners_render_instance_t>(this, push_damage, shown_on);
    if (instance->has_instances())
    {
        instances.push_back(std::move(instance));
    }
}

void attach(wayfire_view view)
{
    auto toplevel = wf::toplevel_cast(view);
    if (!toplevel || (view->role != wf::VIEW_ROLE_TOPLEVEL))
    {
        return;
    }

    auto tmgr = view->get_transformed_node();
    if (tmgr->get_transformer<corners_node_t>(NAME))
    {
        return;
    }

    // Below every other transformer, so the corners move with the window.
    tmgr->add_transformer(std::make_shared<corners_node_t>(toplevel), 0, NAME);
}

void detach(wayfire_view view)
{
    view->get_transformed_node()->rem_transformer<corners_node_t>(NAME);
}

void release()
{
    if (program)
    {
        OpenGL::render_begin();
        program->free_resources();
        OpenGL::render_end();
        delete program;
        program = nullptr;
    }
}
}
