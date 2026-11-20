#include <algorithm>

#include <wayfire/per-output-plugin.hpp>
#include <wayfire/view.hpp>
#include <wayfire/workarea.hpp>
#include <wayfire/matcher.hpp>
#include <wayfire/workspace-set.hpp>
#include <wayfire/output.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/txn/transaction-manager.hpp>

#include "deco-subsurface.hpp"
#include "corners.hpp"
#include "wayfire/core.hpp"
#include "wayfire/plugin.hpp"
#include "wayfire/signal-provider.hpp"
#include "wayfire/toplevel-view.hpp"
#include "wayfire/toplevel.hpp"

class strata_decoration : public wf::plugin_interface_t
{
    wf::view_matcher_t ignore_views{"decoration/ignore_views"};

    wf::signal::connection_t<wf::txn::new_transaction_signal> on_new_tx =
        [=] (wf::txn::new_transaction_signal *ev)
    {
        // For each transaction, we need to consider what happens with participating views
        for (const auto& obj : ev->tx->get_objects())
        {
            if (auto toplevel = std::dynamic_pointer_cast<wf::toplevel_t>(obj))
            {
                // First check whether the toplevel already has decoration
                // In that case, we should just set the correct margins
                if (auto deco = toplevel->get_data<wf::strata_decorator_t>())
                {
                    toplevel->pending().margins = deco->get_margins(toplevel->pending());
                    continue;
                }

                // Second case: the view is already mapped, or the transaction does not map it.
                // The view is not being decorated, so nothing to do here.
                if (toplevel->current().mapped || !toplevel->pending().mapped)
                {
                    continue;
                }

                // Third case: the transaction will map the toplevel.
                auto view = wf::find_view_for_toplevel(toplevel);
                wf::dassert(view != nullptr, "Mapping a toplevel means there must be a corresponding view!");
                if (should_decorate_view(view))
                {
                    adjust_new_decorations(view);
                }
            }
        }
    };

    wf::signal::connection_t<wf::view_decoration_state_updated_signal> on_decoration_state_changed =
        [=] (wf::view_decoration_state_updated_signal *ev)
    {
        update_view_decoration(ev->view);
    };

    // allows criteria containing maximized or floating check
    wf::signal::connection_t<wf::view_tiled_signal> on_view_tiled =
        [=] (wf::view_tiled_signal *ev)
    {
        update_view_decoration(ev->view);
    };

    wf::signal::connection_t<wf::view_mapped_signal> on_view_mapped =
        [=] (wf::view_mapped_signal *ev)
    {
        strata_corners::attach(ev->view);
        fit_in_workarea(ev->view);
    };

    /* A new window never starts under the menu bar or the dock: one taller or
     * wider than the free space is made to fit it, and one placed above it is
     * moved down. (This runs after the placement plugin has placed it.) */
    static void fit_in_workarea(wayfire_view view)
    {
        auto toplevel = wf::toplevel_cast(view);
        if (!toplevel || (view->role != wf::VIEW_ROLE_TOPLEVEL) || !view->get_output() ||
            toplevel->parent || toplevel->pending_fullscreen() || toplevel->pending_tiled_edges())
        {
            return;
        }

        auto area = view->get_output()->workarea->get_workarea();
        auto g    = toplevel->get_pending_geometry();
        auto fit  = g;
        fit.width  = std::min(g.width, area.width);
        fit.height = std::min(g.height, area.height);
        fit.x = std::clamp(g.x, area.x, area.x + area.width - fit.width);
        fit.y = std::clamp(g.y, area.y, area.y + area.height - fit.height);
        if ((fit.width != g.width) || (fit.height != g.height))
        {
            // Keep it centred where the placement plugin centred it.
            fit.x = std::clamp(g.x + (g.width - fit.width) / 2, area.x, area.x + area.width - fit.width);
            fit.y = std::clamp(g.y + (g.height - fit.height) / 2, area.y, area.y + area.height - fit.height);
        }

        if (fit != g)
        {
            toplevel->set_geometry(fit);
        }
    }

  public:
    void init() override
    {
        wf::get_core().connect(&on_view_mapped);
        wf::get_core().connect(&on_decoration_state_changed);
        wf::get_core().tx_manager->connect(&on_new_tx);
        wf::get_core().connect(&on_view_tiled);

        for (auto& view : wf::get_core().get_all_views())
        {
            update_view_decoration(view);
            if (view->is_mapped())
            {
                strata_corners::attach(view);
            }
        }
    }

    void fini() override
    {
        for (auto view : wf::get_core().get_all_views())
        {
            strata_corners::detach(view);
            if (auto toplevel = wf::toplevel_cast(view))
            {
                remove_decoration(toplevel);
                wf::get_core().tx_manager->schedule_object(toplevel->toplevel());
            }
        }

        strata_corners::release();
    }

    /**
     * Uses view_matcher_t to match whether the given view needs to be
     * ignored for decoration
     *
     * @param view The view to match
     * @return Whether the given view should be decorated?
     */
    bool ignore_decoration_of_view(wayfire_view view)
    {
        return ignore_views.matches(view);
    }

    bool should_decorate_view(wayfire_toplevel_view view)
    {
        return view->should_be_decorated() && !ignore_decoration_of_view(view);
    }

    void adjust_new_decorations(wayfire_toplevel_view view)
    {
        auto toplevel = view->toplevel();

        toplevel->store_data(std::make_unique<wf::strata_decorator_t>(view));
        auto deco     = toplevel->get_data<wf::strata_decorator_t>();
        auto& pending = toplevel->pending();
        pending.margins = deco->get_margins(pending);

        if (!pending.fullscreen && !pending.tiled_edges)
        {
            pending.geometry = wf::expand_geometry_by_margins(pending.geometry, pending.margins);
            if (view->get_output())
            {
                pending.geometry = wf::clamp(pending.geometry, view->get_output()->workarea->get_workarea());
            }
        }
    }

    void remove_decoration(wayfire_toplevel_view view)
    {
        view->toplevel()->erase_data<wf::strata_decorator_t>();
        auto& pending = view->toplevel()->pending();
        if (!pending.fullscreen && !pending.tiled_edges)
        {
            pending.geometry = wf::shrink_geometry_by_margins(pending.geometry, pending.margins);
        }

        pending.margins = {0, 0, 0, 0};
    }

    void update_view_decoration(wayfire_view view)
    {
        if (auto toplevel = wf::toplevel_cast(view))
        {
            if (should_decorate_view(toplevel))
            {
                adjust_new_decorations(toplevel);
            } else
            {
                remove_decoration(toplevel);
            }

            wf::get_core().tx_manager->schedule_object(toplevel->toplevel());
        }
    }
};

DECLARE_WAYFIRE_PLUGIN(strata_decoration);
