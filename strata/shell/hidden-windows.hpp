// SPDX-License-Identifier: GPL-3.0-or-later
// Hidden windows (⌘H, Hide in the app menu): as far as Wayfire knows they
// are minimized, but they are not minimized into the Dock, so they get no
// picture there and don't shrink into it. Strata keeps the list, so the
// Command key, the menu bar and the Dock all agree on it.
// Original freemac code.
#pragma once

#include <set>
#include <wayfire/core.hpp>
#include <wayfire/object.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/window-manager.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>

class strata_hidden_data : public wf::custom_data_t
{
  public:
    std::set<uint32_t> ids;
};

namespace strata_hidden
{
inline std::set<uint32_t>& ids()
{
    return wf::get_core().get_data_safe<strata_hidden_data>()->ids;
}

inline void hide(wayfire_toplevel_view view)
{
    if (!view || view->minimized)
    {
        return;
    }

    ids().insert(view->get_id());
    view->set_minimize_hint({0, 0, 0, 0});   // just go, without shrinking into the Dock
    wf::get_core().default_wm->minimize_request(view, true);
}

/* The hidden windows still hidden; ones brought back or closed drop off. */
inline std::set<uint32_t> current()
{
    auto& list = ids();
    for (auto it = list.begin(); it != list.end();)
    {
        auto view = wf::toplevel_cast(wf::ipc::find_view_by_id(*it));
        if (!view || !view->minimized)
        {
            it = list.erase(it);
        } else
        {
            ++it;
        }
    }

    return list;
}
}
