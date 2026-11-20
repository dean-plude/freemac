#pragma once
/* Strata: rounded bottom corners for every window (see corners.cpp). */
#include <wayfire/view.hpp>

namespace strata_corners
{
void attach(wayfire_view view);
void detach(wayfire_view view);
/* Free the shader; call once, when the plugin unloads. */
void release();
}
