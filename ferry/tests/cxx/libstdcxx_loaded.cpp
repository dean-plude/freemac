/* SPDX-License-Identifier: GPL-3.0-or-later
 * An error libc++ throws itself is caught by a Mac catch clause even when
 * GNU libstdc++ is already in the process (this system's OpenGL brings it
 * in): OBS's official download died on this (freemac 1.263). Run with
 * libstdc++ preloaded. */
#include <cstdio>
#include <filesystem>
int main() {
    try {
        std::filesystem::create_directory("/nonexistent-dir-ferry/a/b");
        std::puts("no throw");
    } catch (const std::filesystem::filesystem_error &e) {
        std::puts("caught filesystem_error");
    } catch (...) {
        std::puts("caught something else");
    }
    return 0;
}
