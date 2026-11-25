-- Loads packages/odimac/hyprland.lua against a stand-in for Hyprland's `hl`
-- API (and Omarchy's `o.bind`) and replays key presses, window and idle
-- events, and a reload of the configuration. Run by
-- tests/session-test.sh, which sets ODIMAC_RUN and HOME to scratch
-- directories. This checks the logic in the config, not Hyprland itself.
local config = assert(arg[1], "usage: session-test.lua path/to/hyprland.lua")
local run_dir = assert(os.getenv("ODIMAC_RUN"))

local S = { binds = {}, handlers = {}, execs = {}, rules = {}, ws = { name = "1", special = false }, panel = nil }

local function fire(event, ...)
    for _, cb in ipairs(S.handlers[event] or {}) do cb(...) end
end
local function maker(name)
    return function(a, b) return { dsp = name, arg = a, arg2 = b } end
end
local function namespace(prefix)
    return setmetatable({}, { __index = function(_, k) return maker(prefix .. k) end })
end
local noop = function() return {} end

hl = {
    monitor = noop, env = noop, timer = noop,
    config = function(c) S.config = c end,
    window_rule = function(r) S.rules[r.name] = r end,
    bind = function(keys, d, opts)
        S.binds[keys] = S.binds[keys] or {}
        table.insert(S.binds[keys], { d = d, opts = opts or {} })
    end,
    on = function(event, cb)
        S.handlers[event] = S.handlers[event] or {}
        table.insert(S.handlers[event], cb)
    end,
    exec_cmd = function(cmd) table.insert(S.execs, cmd) end,
    get_active_workspace = function() return S.ws end,
    dispatch = function(d)
        assert(type(d) == "table" and d.dsp, "hl.dispatch needs a dispatcher")
        if d.dsp == "focus" and d.arg.workspace then
            local name = tostring(d.arg.workspace):gsub("^name:", "")
            if not name:match("^[em][+-]") then
                S.ws = { name = name, special = false }
                fire("workspace.active", S.ws)
            end
        elseif d.dsp == "exec_cmd" then
            table.insert(S.execs, d.arg)
        elseif d.dsp == "window.move" and d.arg.window then
            d.arg.window.moved_to, d.arg.window.followed = d.arg.workspace, d.arg.follow
        elseif d.dsp == "window.fullscreen" and d.arg.window then
            d.arg.window.is_fullscreen = true
        elseif d.dsp == "dpms" then
            S.panel = d.arg.action
        end
    end,
    dsp = setmetatable({
        window = namespace("window."), workspace = namespace("workspace."),
        group = namespace("group."), cursor = namespace("cursor."),
    }, { __index = function(_, k) return maker(k) end }),
}

-- Omarchy's helper for bindings, as far as the config uses it.
o = {
    bind_commands = {},
    bind = function(keys, description, d, opts)
        opts = opts or {}
        opts.description = description
        hl.bind(keys, d, opts)
    end,
}

-- What Hyprland does on a reload: forget everything the config set up, and
-- run it again in a fresh Lua state. Windows and workspaces stay.
local function reload()
    S.binds, S.handlers, S.rules = {}, {}, {}
    odimac = nil
    dofile(config)
end

local failed = false
local function check(what, ok)
    print((ok and "ok   " or "FAIL ") .. what)
    if not ok then failed = true end
end
local function press(keys)
    assert(S.binds[keys], "no binding for " .. keys)
    for _, b in ipairs(S.binds[keys]) do
        if type(b.d) == "function" then b.d() else hl.dispatch(b.d) end
    end
end
local function mode_file()
    local f = io.open(run_dir .. "/odimac-mode")
    if not f then return nil end
    local line = f:read("l")
    f:close()
    return line
end
local function count(pattern)
    local n = 0
    for _, cmd in ipairs(S.execs) do
        if cmd:find(pattern, 1, true) then n = n + 1 end
    end
    return n
end
local function showing(ws, mode)
    return S.ws.name == ws and mode_file() == mode and odimac.current() == mode
end

local ok, err = pcall(dofile, config)
check("the config loads" .. (ok and "" or (": " .. tostring(err))), ok)
if not ok then os.exit(1) end

fire("hyprland.start")
check("starts on the Mac display", showing("display", "display"))
check("starts its services, once the session's environment is with systemd",
    count("dbus-update-activation-environment --systemd --all; systemctl --user restart odimac.target") == 1)

press("CTRL + ALT + 2")
check("Ctrl+Alt+2 shows gaming and records it", showing("game", "game"))
check("and starts Moonlight's launcher", count("/game") == 1)
press("CTRL + ALT + 1")
press("CTRL + ALT + 2")
check("a second switch does not start it again", count("/game") == 1 and showing("game", "game"))

odimac.pid("4242", "display")
local receiver = { pid = 4242, class = "", workspace = S.ws }
fire("window.open", receiver)
check("the receiver's window, opening during a game, goes to its own workspace",
    receiver.moved_to == "name:display" and receiver.followed == false and receiver.is_fullscreen)
check("without taking the game off the screen", showing("game", "game"))
local moonlight = { pid = 7, class = "com.moonlight_stream.Moonlight", workspace = S.ws }
fire("window.open", moonlight)
check("Moonlight's window is made full screen where it is", moonlight.is_fullscreen and moonlight.moved_to == nil)
odimac.pid(99, "game")
local stream = { pid = 99, class = "SDL", workspace = { name = "1" } }
fire("window.open", stream)
check("a window of the launcher's Moonlight is recognised by its process", stream.moved_to == "name:game" and stream.is_fullscreen)

press("CTRL + ALT + 3")
check("Ctrl+Alt+3 shows the desktop", showing("1", "desktop"))
local firefox = { pid = 500, class = "firefox", workspace = S.ws }
fire("window.open", firefox)
check("desktop windows are left alone", firefox.moved_to == nil and not firefox.is_fullscreen)
hl.dispatch(hl.dsp.focus({ workspace = "3" }))
check("Omarchy's own workspace keys stay on the desktop", showing("3", "desktop"))
press("CTRL + ALT + 1")
check("Ctrl+Alt+1 returns to the Mac display", showing("display", "display"))
press("CTRL + ALT + 3")
check("the desktop comes back on the workspace it was left on", showing("3", "desktop"))

-- Omarchy reloads the configuration when a monitor is plugged in or a theme
-- is chosen. Moonlight is running, the receiver has its window.
reload()
check("after a reload the keys are there again", S.binds["CTRL + ALT + 1"] ~= nil and showing("3", "desktop"))
press("CTRL + ALT + 2")
check("a reload does not make Ctrl+Alt+2 start a second Moonlight", count("/game") == 1 and showing("game", "game"))
local again = { pid = 4242, class = "", workspace = S.ws }
fire("window.open", again)
check("nor forget which process is the receiver", again.moved_to == "name:display")
press("CTRL + ALT + 3")
check("nor which desktop workspace was left", showing("3", "desktop"))
check("nor start the services a second time", count("odimac.target") == 1)

odimac.ended("game")
check("Moonlight quitting in the background changes nothing", showing("3", "desktop"))
press("CTRL + ALT + 2")
check("after it quit, Ctrl+Alt+2 starts it again", count("/game") == 2 and showing("game", "game"))
odimac.ended("game")
check("Moonlight quitting while showing returns to the Mac display", showing("display", "display"))

odimac.idle()
check("idle on the Mac display stays there", showing("display", "display"))
press("CTRL + ALT + 3")
odimac.idle()
check("idle on the desktop returns to the Mac display", showing("display", "display"))

-- Omarchy's launcher and its keys work on the Mac display too.
local terminal = { pid = 600, class = "com.mitchellh.ghostty", workspace = S.ws }
fire("window.open", terminal)
check("a program started on the Mac display opens on the desktop, which comes to the front",
    terminal.moved_to == "3" and not terminal.is_fullscreen and showing("3", "desktop"))

odimac.panel("off")
check("the power policy can turn the panel off", S.panel == "disable")
odimac.panel("on")
check("and on", S.panel == "enable")
check("an unknown mode is refused", odimac.mode("bogus") ~= "ok" and showing("3", "desktop"))
local everywhere, listed = true, true
for _, keys in ipairs({ "CTRL + ALT + 1", "CTRL + ALT + 2", "CTRL + ALT + 3" }) do
    for _, b in ipairs(S.binds[keys] or { { opts = {} } }) do
        everywhere = everywhere and b.opts.dont_inhibit == true and b.opts.locked == true
        listed = listed and type(b.opts.description) == "string" and o.bind_commands[b.d] ~= nil
    end
end
check("the mode keys also work while a game holds the keyboard", everywhere)
check("and are listed in Omarchy's keybindings menu, which can run them", listed)
for _, name in ipairs({ "odimac-receiver", "odimac-moonlight" }) do
    local r = S.rules[name]
    check(name .. ": full screen on its workspace, where Omarchy's screensaver and lock stay off it",
        r ~= nil and r.fullscreen == true and r.idle_inhibit == "fullscreen" and r.workspace:find("^name:") ~= nil)
end
local render = S.config and S.config.render or {}
check("nothing asks the 5K driver for a modeset when a window goes full screen",
    render.cm_auto_hdr == 0 and render.send_content_type == false and render.direct_scanout == 0)

-- A new session after a crash finds the old one's notes.
hl.dispatch(hl.dsp.focus({ workspace = "name:game" }))
fire("hyprland.start")
press("CTRL + ALT + 2")
check("a new session starts Moonlight afresh", count("/game") == 3)

os.exit(failed and 1 or 0)
