// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * Apps' own global shortcuts (freemac 1.215, Ferry 0.41.0). A Mac app can
 * register a key combination that reaches it whichever app is in front
 * (Carbon's RegisterEventHotKey): Spectacle's and ShiftIt's window
 * shortcuts, Flycut's clipboard key. Wayland lets no app see the keys typed
 * in another, so Ferry asks Strata instead:
 *
 *   strata/hotkeys/register {"key": EVDEV CODE,
 *                            "modifiers": ["command", "option", "control", "shift"],
 *                            "socket": PATH, "tag": N}
 *       -> {"result": "ok", "id": ID}, or an error ("taken" when another
 *          hotkey already has that combination)
 *   strata/hotkeys/unregister {"id": ID}
 *   strata/hotkeys/clear {"socket": PATH}     every hotkey sent to PATH
 *
 * When the combination is pressed, the key goes no further and Strata sends
 * one datagram, {"event": "hotkey", "tag": N, "id": ID}, to the app's socket.
 * Only the registered combinations are ever sent, never other keys, and
 * each needs Command, Option or Control (or is a function key), so no app
 * can collect what is typed by registering plain letters. The socket must
 * be one of the user's own, in $XDG_RUNTIME_DIR/ferry/ and named
 * hotkeys-..., so the datagrams can't be aimed at anything else. When the
 * app has gone (its socket refuses the datagram), its hotkeys are dropped
 * and the key goes on to the focused window as if none were registered.
 *
 * This Wayfire's IPC has no way for a plugin to send an event to the client
 * that asked (later Wayfire versions add command/register-binding), hence
 * the datagram. Original freemac code.
 */
#pragma once

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <linux/input-event-codes.h>

#include <nlohmann/json.hpp>
#include <wayfire/bindings-repository.hpp>
#include <wayfire/config/option.hpp>
#include <wayfire/config/types.hpp>
#include <wayfire/core.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/util.hpp>

class strata_app_hotkeys
{
    struct hotkey
    {
        std::string socket;
        int64_t tag;
        std::shared_ptr<wf::config::option_t<wf::keybinding_t>> option;
        std::unique_ptr<wf::key_callback> callback;
    };

    std::map<int64_t, hotkey> hotkeys;
    int64_t next_id = 1;
    int sender = -1;
    std::vector<std::string> gone;
    wf::wl_idle_call drop_later;

    static constexpr size_t most_per_app = 100;

    static bool allowed_socket(const std::string& path)
    {
        const char *runtime = getenv("XDG_RUNTIME_DIR");
        if (!runtime || !*runtime)
        {
            return false;
        }

        std::string dir = std::string(runtime) + "/ferry/";
        if ((path.compare(0, dir.size(), dir) != 0) || (path.size() >= sizeof(sockaddr_un::sun_path)))
        {
            return false;
        }

        std::string name = path.substr(dir.size());
        if ((name.rfind("hotkeys-", 0) != 0) || (name.find('/') != std::string::npos))
        {
            return false;
        }

        struct stat st;
        return lstat(path.c_str(), &st) == 0 && S_ISSOCK(st.st_mode) && st.st_uid == getuid();
    }

    static bool function_key(uint32_t key)
    {
        return (key >= KEY_F1 && key <= KEY_F10) || key == KEY_F11 || key == KEY_F12 ||
               (key >= KEY_F13 && key <= KEY_F24);
    }

    bool deliver(int64_t id, const hotkey& h)
    {
        if (sender < 0)
        {
            sender = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
        }

        if ((sender < 0) || !allowed_socket(h.socket))
        {
            return false;
        }

        sockaddr_un addr{};
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, h.socket.c_str(), sizeof(addr.sun_path) - 1);
        std::string message = nlohmann::json{{"event", "hotkey"}, {"tag", h.tag}, {"id", id}}.dump();
        return sendto(sender, message.data(), message.size(), MSG_DONTWAIT | MSG_NOSIGNAL,
            (sockaddr*)&addr, sizeof(addr)) == (ssize_t)message.size();
    }

    void drop_socket(const std::string& socket)
    {
        for (auto it = hotkeys.begin(); it != hotkeys.end();)
        {
            if (it->second.socket == socket)
            {
                wf::get_core().bindings->rem_binding(it->second.callback.get());
                it = hotkeys.erase(it);
            } else
            {
                ++it;
            }
        }
    }

  public:
    ~strata_app_hotkeys()
    {
        if (sender >= 0)
        {
            close(sender);
        }
    }

    nlohmann::json register_hotkey(nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "key", number_integer);
        WFJSON_EXPECT_FIELD(data, "socket", string);
        WFJSON_EXPECT_FIELD(data, "tag", number_integer);
        WFJSON_OPTIONAL_FIELD(data, "modifiers", array);
        int64_t key = data["key"];
        std::string socket = data["socket"];
        if ((key <= 0) || (key > KEY_MAX))
        {
            return wf::ipc::json_error("no such key");
        }

        if (!allowed_socket(socket))
        {
            return wf::ipc::json_error("not an app's hotkey socket");
        }

        uint32_t mods = 0;
        if (data.count("modifiers"))
        {
            for (auto& name : data["modifiers"])
            {
                if (!name.is_string())
                {
                    return wf::ipc::json_error("modifiers are names");
                }

                std::string n = name;
                if (n == "command")
                {
                    mods |= wf::KEYBOARD_MODIFIER_LOGO;
                } else if (n == "option")
                {
                    mods |= wf::KEYBOARD_MODIFIER_ALT;
                } else if (n == "control")
                {
                    mods |= wf::KEYBOARD_MODIFIER_CTRL;
                } else if (n == "shift")
                {
                    mods |= wf::KEYBOARD_MODIFIER_SHIFT;
                } else
                {
                    return wf::ipc::json_error("no such modifier");
                }
            }
        }

        /* Plain keys and Shift with a key are typing, which stays the
         * focused app's own. */
        if (!(mods & (wf::KEYBOARD_MODIFIER_LOGO | wf::KEYBOARD_MODIFIER_ALT | wf::KEYBOARD_MODIFIER_CTRL)) &&
            !function_key(key))
        {
            return wf::ipc::json_error("a hotkey needs Command, Option or Control");
        }

        wf::keybinding_t binding{mods, (uint32_t)key};
        size_t mine = 0;
        for (auto& [id, h] : hotkeys)
        {
            if (h.option->get_value() == binding)
            {
                return wf::ipc::json_error("taken");
            }

            mine += (h.socket == socket);
        }

        if (mine >= most_per_app)
        {
            return wf::ipc::json_error("too many hotkeys");
        }

        int64_t id = next_id++;
        hotkey h;
        h.socket   = socket;
        h.tag      = data["tag"];
        h.option   = std::make_shared<wf::config::option_t<wf::keybinding_t>>("strata-app-hotkey", binding);
        h.callback = std::make_unique<wf::key_callback>([this, id] (const wf::keybinding_t&)
        {
            auto it = hotkeys.find(id);
            if (it == hotkeys.end())
            {
                return false;
            }

            if (deliver(id, it->second))
            {
                return true;
            }

            /* The app has gone: forget its hotkeys once the key is handled,
             * and let this key through. */
            gone.push_back(it->second.socket);
            drop_later.run_once([this] ()
            {
                for (auto& s : gone)
                {
                    drop_socket(s);
                }

                gone.clear();
            });
            return false;
        });
        wf::get_core().bindings->add_key(h.option, h.callback.get());
        hotkeys.emplace(id, std::move(h));
        auto out = wf::ipc::json_ok();
        out["id"] = id;
        return out;
    }

    nlohmann::json unregister_hotkey(nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "id", number_integer);
        auto it = hotkeys.find(data["id"].get<int64_t>());
        if (it == hotkeys.end())
        {
            return wf::ipc::json_error("no such hotkey");
        }

        wf::get_core().bindings->rem_binding(it->second.callback.get());
        hotkeys.erase(it);
        return wf::ipc::json_ok();
    }

    nlohmann::json clear(nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "socket", string);
        drop_socket(data["socket"]);
        return wf::ipc::json_ok();
    }
};
