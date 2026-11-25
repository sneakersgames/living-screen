-- OpenDisplay iMac on Omarchy: the Mac display and gaming as two more
-- environments of Omarchy's own Hyprland session, each on a workspace of its
-- own, so changing between them is a change of workspace and nothing more.
--
--   workspace "display"   the OpenDisplay receiver, full screen (Ctrl+Alt+1)
--   workspace "game"      Moonlight, full screen               (Ctrl+Alt+2)
--   every other workspace Omarchy's desktop                    (Ctrl+Alt+3)
--
-- Loaded from ~/.config/hypr/hyprland.lua by the line `odimac-setup` adds
-- there, after Omarchy's own configuration. The scripts in /usr/lib/odimac
-- talk to the functions in `odimac` below with `hyprctl eval`.
--
-- Omarchy reloads this file with the rest of the configuration (a monitor
-- plugged in, a theme chosen), and every reload starts with an empty Lua
-- state. What has to outlive that is therefore kept in small files in the
-- session's runtime directory, not in variables.

local lib     = os.getenv("ODIMAC_LIB") or "/usr/lib/odimac"
local run_dir = os.getenv("ODIMAC_RUN") or os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local log     = "systemd-cat -t odimac-mode "

local DISPLAY, GAME = "display", "game"

odimac = {}

------------------------------------------------------------------------
-- Notes that outlive a reload
------------------------------------------------------------------------

local function note_path(name) return run_dir .. "/odimac-" .. name end

local function note(name)
    local f = io.open(note_path(name))
    if not f then return nil end
    local value = f:read("*l")
    f:close()
    if value == "" then return nil end
    return value
end

local function set_note(name, value)
    local path = note_path(name)
    if value == nil then
        os.remove(path)
        return
    end
    local f = io.open(path .. ".new", "w")
    if not f then return end
    f:write(tostring(value), "\n")
    f:close()
    os.rename(path .. ".new", path)
end

------------------------------------------------------------------------
-- The three environments
------------------------------------------------------------------------

-- Which environment a workspace belongs to.
local function mode_of(ws)
    if ws and ws.name == DISPLAY then return "display" end
    if ws and ws.name == GAME then return "game" end
    return "desktop"
end

-- The desktop workspace to return to.
local function last_desktop() return note("desktop") or "1" end

function odimac.current()
    return mode_of(hl.get_active_workspace())
end

-- Switch to "display", "game" or "desktop". Moonlight starts on first use.
function odimac.mode(name)
    if name == "display" then
        hl.dispatch(hl.dsp.focus({ workspace = "name:" .. DISPLAY }))
    elseif name == "game" then
        hl.dispatch(hl.dsp.focus({ workspace = "name:" .. GAME }))
        if not note("game.pid") then
            set_note("game.pid", "starting")
            hl.exec_cmd(log .. lib .. "/game")
        end
    elseif name == "desktop" then
        hl.dispatch(hl.dsp.focus({ workspace = last_desktop() }))
    else
        return "unknown mode " .. tostring(name)
    end
    return "ok"
end

-- A mode's program has exited: back to the Mac display if it was showing.
function odimac.ended(name)
    if name == "game" then set_note("game.pid", nil) end
    if odimac.current() == name then odimac.mode("display") end
end

-- No input for MODE_IDLE_RETURN seconds (lib/mode watch).
function odimac.idle()
    if odimac.current() ~= "display" then odimac.mode("display") end
end

-- receiver-loop and game say which process's windows are theirs.
function odimac.pid(pid, kind)
    if kind == "display" or kind == "game" then set_note(kind .. ".pid", pid) end
end

-- For odimac-powerd: "on" or "off".
function odimac.panel(state)
    hl.dispatch(hl.dsp.dpms({ action = state == "off" and "disable" or "enable" }))
end

-- odimac-powerd reads the mode to keep the panel lit outside the Mac display.
hl.on("workspace.active", function(ws)
    local mode = mode_of(ws)
    if mode == "desktop" and ws and not ws.special then set_note("desktop", ws.name) end
    set_note("mode", mode)
end)

-- The receiver's and Moonlight's windows belong on their own workspaces,
-- full screen, whichever environment is showing when they open.
local function kind_of(w)
    local pid = tostring(w.pid)
    if pid == note("display.pid") then return "display" end
    if pid == note("game.pid") then return "game" end
    local class = string.lower(w.class or "")
    if class:find("moonlight", 1, true) then return "game" end
    if class:find("opendisplay", 1, true) or class:find("od-receiver", 1, true) then return "display" end
end

hl.on("window.open", function(w)
    local kind = kind_of(w)
    local on = w.workspace and w.workspace.name
    if kind then
        local name = kind == "game" and GAME or DISPLAY
        if on ~= name then
            hl.dispatch(hl.dsp.window.move({ window = w, workspace = "name:" .. name, follow = false }))
        end
        hl.dispatch(hl.dsp.window.fullscreen({ window = w, action = "set", mode = "fullscreen" }))
    elseif on == DISPLAY or on == GAME then
        -- Anything else was started while the Mac display or a game was
        -- showing (the launcher, a key): it opens on the desktop, and the
        -- desktop comes to the front with it.
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = last_desktop(), follow = false }))
        odimac.mode("desktop")
    end
end)

-- Where the windows' classes are what they say they are, these rules place
-- them before they are shown; the handler above covers the rest.
--
-- idle_inhibit: while the Mac display or a game is on the panel, nobody
-- touches the iMac's own keyboard, and Omarchy's screensaver and lock must
-- not cover the picture. It holds only while that workspace is showing, so
-- the desktop idles as Omarchy has it. On the Mac display odimac-powerd
-- decides when the panel is lit.
hl.window_rule({
    name  = "odimac-receiver",
    match = { class = "^app\\.opendisplay\\.Receiver$" },
    workspace = "name:" .. DISPLAY .. " silent",
    fullscreen = true,
    idle_inhibit = "fullscreen",
})
hl.window_rule({
    name  = "odimac-moonlight",
    match = { class = "^com\\.moonlight_stream\\.Moonlight$" },
    workspace = "name:" .. GAME .. " silent",
    fullscreen = true,
    idle_inhibit = "fullscreen",
})

-- Nothing that makes Hyprland change the panel's signal when a window goes
-- full screen or leaves it (HDR, content type, direct scanout): the panel is
-- plain SDR, and each such change is a modeset for the 5K driver, which had
-- a crash in exactly that path.
hl.config({
    render = {
        cm_auto_hdr       = 0,
        send_content_type = false,
        direct_scanout    = 0,
    },
})

-- Once per session, not per reload. The services are systemd user units
-- (odimac.target): the receiver, odimac-powerd, the return to the Mac display
-- after a time without input, and the pointer shield. They need the session's
-- environment, which Omarchy hands to systemd at this same moment: asking
-- again here means it is there before they start.
hl.on("hyprland.start", function()
    for _, name in ipairs({ "display.pid", "game.pid", "desktop" }) do set_note(name, nil) end
    set_note("mode", "display")
    hl.dispatch(hl.dsp.focus({ workspace = "name:" .. DISPLAY }))
    hl.exec_cmd("dbus-update-activation-environment --systemd --all; systemctl --user restart odimac.target")
end)

------------------------------------------------------------------------
-- Keys
------------------------------------------------------------------------

-- They work everywhere: on the lock screen's far side too (locked), and
-- while Moonlight holds the keyboard for a game (dont_inhibit).
local function key(keys, description, name)
    local function switch() odimac.mode(name) end
    local opts = { locked = true, dont_inhibit = true }
    if o and o.bind then
        -- Omarchy's keybindings menu lists the key, and can run it.
        if o.bind_commands then o.bind_commands[switch] = lib .. "/mode " .. name end
        o.bind(keys, description, switch, opts)
    else
        hl.bind(keys, switch, opts)
    end
end
key("CTRL + ALT + 1", "Mac display", "display")
key("CTRL + ALT + 2", "Gaming", "game")
key("CTRL + ALT + 3", "Desktop", "desktop")
