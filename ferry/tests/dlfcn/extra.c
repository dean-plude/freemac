/* SPDX-License-Identifier: GPL-3.0-or-later
 * A loadable bundle (MH_BUNDLE) for the libsystem_dlsym test, built with
 * -bundle -undefined dynamic_lookup: main_helper is the program's own,
 * found when the bundle is loaded. */
int main_helper(int x);

int bundle_value(void) { return main_helper(21); }
