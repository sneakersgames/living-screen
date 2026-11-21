-- Loads packages/odimac/hyprland.lua against a stand-in for Hyprland's `hl`
-- API and replays key presses, window and idle events. Run by
-- tests/session-test.sh, which sets ODIMAC_RUN and HOME to scratch
-- directories. This checks the logic in the config, not Hyprland itself.
local config = assert(arg[1], "usage: session-test.lua path/to/hyprland.lua")
local run_dir = assert(os.getenv("ODIMAC_RUN"))

local S = { binds = {}, handlers = {}, execs = {}, ws = { name = "1", special = false }, panel = nil }

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
    monitor = noop, env = noop, config = noop, window_rule = noop, timer = noop,
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
check("starts the receiver, the power policy, the idle watcher and the bar",
    count("/receiver-loop") == 1 and count("/powerd") == 1 and count("/mode watch") == 1 and count("qs -p") == 1)

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
press("SUPER + code:12")
check("Cmd+3 goes to workspace 3", showing("3", "desktop"))
press("CTRL + ALT + 1")
check("Ctrl+Alt+1 returns to the Mac display", showing("display", "display"))
press("CTRL + ALT + 3")
check("the desktop comes back on the workspace it was left on", showing("3", "desktop"))

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

local before = count("foot")
press("SUPER + Return")
check("a program asked for on the Mac display opens on the desktop", showing("3", "desktop") and count("foot") == before + 1)

odimac.panel("off")
check("the power policy can turn the panel off", S.panel == "off")
odimac.panel("on")
check("and on", S.panel == "on")
check("an unknown mode is refused", odimac.mode("bogus") ~= "ok" and showing("3", "desktop"))
local everywhere = true
for _, keys in ipairs({ "CTRL + ALT + 1", "CTRL + ALT + 2", "CTRL + ALT + 3", "XF86MonBrightnessUp", "XF86AudioMute" }) do
    for _, b in ipairs(S.binds[keys] or { { opts = {} } }) do
        everywhere = everywhere and b.opts.dont_inhibit == true
    end
end
check("the mode, brightness and volume keys also work while a game holds the keyboard", everywhere)

os.exit(failed and 1 or 0)
