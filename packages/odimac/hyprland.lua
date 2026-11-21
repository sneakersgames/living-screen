-- The OpenDisplay iMac appliance's one session: Hyprland shows all three
-- environments, each on workspaces of its own, so changing between them is a
-- change of workspace and nothing more.
--
--   workspace "display"   the OpenDisplay receiver, full screen (Ctrl+Alt+1)
--   workspace "game"      Moonlight, full screen               (Ctrl+Alt+2)
--   workspaces 1 to 10    the desktop, with the Quickshell bar (Ctrl+Alt+3)
--
-- Started by odimac-kiosk.service through /usr/lib/odimac/session. The
-- scripts beside it talk to the functions in `odimac` below with
-- `hyprctl eval`. Window management on the desktop follows Omarchy's
-- defaults (https://omarchy.org). Your own settings go in
-- ~/.config/hypr/odimac.lua, which is read last and can change anything here.

local lib      = os.getenv("ODIMAC_LIB") or "/usr/lib/odimac"
local share    = os.getenv("ODIMAC_SHARE") or "/usr/share/odimac"
local run_dir  = os.getenv("ODIMAC_RUN") or os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local log      = "systemd-cat -t odimac-mode "
local terminal = "foot"
local menu     = "fuzzel"
local browser  = "firefox"
local files    = "nautilus --new-window"
local mod      = "SUPER" -- the Command key on an Apple keyboard

-- Retina: a 2560x1440 desktop on the 5K panel. The receiver reports this
-- scale to the Mac, which then builds a "looks like 2560x1440" display.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 })

hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        resize_on_border        = true,
        extend_border_grab_area = 8,
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        -- The 2017 Radeon also shows the Mac's stream and Moonlight's.
        blur   = { enabled = false },
        shadow = { enabled = false },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    input = { kb_layout = "us", follow_mouse = 1 },
    cursor = { inactive_timeout = 3 },
    -- Nothing that makes Hyprland change the panel's signal when a window
    -- goes full screen or leaves it (HDR, content type, direct scanout): the
    -- panel is plain SDR, and each such change is a modeset for the 5K
    -- driver, which had a crash in exactly that path.
    render = {
        cm_auto_hdr       = 0,
        send_content_type = false,
        direct_scanout    = 0,
    },
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = "rgb(000000)",
        -- The service starts Hyprland itself, without start-hyprland.
        disable_watchdog_warning = true,
        -- odimac-powerd alone decides when the panel is lit.
        key_press_enables_dpms   = false,
        mouse_move_enables_dpms  = false,
    },
})

------------------------------------------------------------------------
-- The three environments
------------------------------------------------------------------------

odimac = {}

local DISPLAY, GAME = "display", "game"
local last_desktop  = "1"    -- the desktop workspace to return to
local kinds         = {}     -- pid -> "display" or "game", told by the scripts
local game_running  = false

-- Which environment a workspace belongs to.
local function mode_of(ws)
    if ws and ws.name == DISPLAY then return "display" end
    if ws and ws.name == GAME then return "game" end
    return "desktop"
end

-- odimac-powerd reads this to keep the panel lit outside the Mac display.
local function record(mode)
    local path = run_dir .. "/odimac-mode"
    local f = io.open(path .. ".new", "w")
    if not f then return end
    f:write(mode, "\n")
    f:close()
    os.rename(path .. ".new", path)
end

function odimac.current()
    return mode_of(hl.get_active_workspace())
end

-- Switch to "display", "game" or "desktop". Moonlight starts on first use.
function odimac.mode(name)
    if name == "display" then
        hl.dispatch(hl.dsp.focus({ workspace = "name:" .. DISPLAY }))
    elseif name == "game" then
        hl.dispatch(hl.dsp.focus({ workspace = "name:" .. GAME }))
        if not game_running then
            game_running = true
            hl.exec_cmd(log .. lib .. "/game")
        end
    elseif name == "desktop" then
        hl.dispatch(hl.dsp.focus({ workspace = last_desktop }))
    else
        return "unknown mode " .. tostring(name)
    end
    return "ok"
end

-- A mode's program has exited: back to the Mac display if it was showing.
function odimac.ended(name)
    if name == "game" then game_running = false end
    if odimac.current() == name then odimac.mode("display") end
end

-- No input for MODE_IDLE_RETURN seconds (lib/mode watch).
function odimac.idle()
    if odimac.current() ~= "display" then odimac.mode("display") end
end

-- receiver-loop and game say which process's windows are theirs.
function odimac.pid(pid, kind)
    kinds[tonumber(pid)] = kind
end

-- For odimac-powerd: "on" or "off".
function odimac.panel(state)
    hl.dispatch(hl.dsp.dpms({ action = state }))
end

hl.on("workspace.active", function(ws)
    local mode = mode_of(ws)
    if mode == "desktop" and ws and not ws.special then last_desktop = ws.name end
    record(mode)
end)

-- The receiver's and Moonlight's windows belong on their own workspaces,
-- full screen, whichever environment is showing when they open.
local function kind_of(w)
    local kind = kinds[w.pid]
    if kind then return kind end
    local class = string.lower(w.class or "")
    if class:find("moonlight", 1, true) then return "game" end
    if class:find("opendisplay", 1, true) or class:find("od-receiver", 1, true) then return "display" end
end

hl.on("window.open", function(w)
    local kind = kind_of(w)
    if not kind then return end
    local name = kind == "game" and GAME or DISPLAY
    if not (w.workspace and w.workspace.name == name) then
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = "name:" .. name, follow = false }))
    end
    hl.dispatch(hl.dsp.window.fullscreen({ window = w, action = "set", mode = "fullscreen" }))
end)

-- If Moonlight's class is what it says it is, the rule places its windows
-- before they are shown; the handler above covers the rest.
hl.window_rule({
    name  = "odimac-moonlight",
    match = { class = "^com\\.moonlight_stream\\.Moonlight$" },
    workspace = "name:" .. GAME .. " silent",
    fullscreen = true,
})

hl.on("hyprland.start", function()
    record("display")
    hl.dispatch(hl.dsp.focus({ workspace = "name:" .. DISPLAY }))
    -- Sound, for Moonlight and the desktop. The units are enabled for every
    -- user as packaged; this makes sure of it.
    hl.exec_cmd("systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber.service")
    hl.exec_cmd("systemd-cat -t odimac-receiver " .. lib .. "/receiver-loop")
    hl.exec_cmd("systemd-cat -t odimac-powerd " .. lib .. "/powerd")
    hl.exec_cmd(log .. lib .. "/mode watch")
    hl.exec_cmd("qs -p " .. share .. "/quickshell")
    hl.exec_cmd("mako")                                   -- notifications
    hl.exec_cmd("systemctl --user start hyprpolkitagent") -- password prompts
    hl.exec_cmd("xdg-user-dirs-update")                   -- Documents, Downloads, ...
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
end)

------------------------------------------------------------------------
-- Keys
------------------------------------------------------------------------

-- The environments, and the keys that act on the iMac itself. They work
-- everywhere: also while Moonlight holds the keyboard for a game.
local always = { locked = true, dont_inhibit = true }
local always_repeat = { locked = true, dont_inhibit = true, repeating = true }
hl.bind("CTRL + ALT + 1", function() odimac.mode("display") end, always)
hl.bind("CTRL + ALT + 2", function() odimac.mode("game") end, always)
hl.bind("CTRL + ALT + 3", function() odimac.mode("desktop") end, always)
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -q set 5%+"), always_repeat)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q -n 2 set 5%-"), always_repeat)
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), always_repeat)
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), always_repeat)
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), always)
-- Start the whole session afresh (the service brings it straight back). This
-- closes every program, Moonlight and the Mac's display included.
hl.bind(mod .. " + SHIFT + Escape", hl.dsp.exit())

-- Programs open on the desktop, from wherever they are asked for.
local function launch(cmd)
    return function()
        if odimac.current() ~= "desktop" then odimac.mode("desktop") end
        hl.exec_cmd(cmd)
    end
end
hl.bind(mod .. " + Return",         launch(terminal))
hl.bind(mod .. " + Space",          launch(menu))
hl.bind(mod .. " + SHIFT + B",      launch(browser))
hl.bind(mod .. " + SHIFT + Return", launch(browser))
hl.bind(mod .. " + SHIFT + F",      launch(files))

-- Windows.
hl.bind(mod .. " + W",       hl.dsp.window.close())
hl.bind(mod .. " + Q",       hl.dsp.window.close())
hl.bind(mod .. " + J",       hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + P",       hl.dsp.window.pseudo())
hl.bind(mod .. " + T",       hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F",       hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
for key, dir in pairs({ left = "l", right = "r", up = "u", down = "d" }) do
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ direction = dir }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.swap({ direction = dir }))
end
hl.bind("ALT + TAB",         hl.dsp.window.cycle_next())
hl.bind("ALT + TAB",         hl.dsp.window.bring_to_top())
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }))
-- Resize with minus and equals.
hl.bind(mod .. " + code:20",         hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
hl.bind(mod .. " + code:21",         hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
hl.bind(mod .. " + SHIFT + code:20", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
hl.bind(mod .. " + SHIFT + code:21", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
-- Groups: several windows in one place, as tabs.
hl.bind(mod .. " + G",                 hl.dsp.group.toggle())
hl.bind(mod .. " + ALT + G",           hl.dsp.window.move({ out_of_group = true }))
hl.bind(mod .. " + ALT + TAB",         hl.dsp.group.next())
hl.bind(mod .. " + ALT + SHIFT + TAB", hl.dsp.group.prev())

-- Desktop workspaces. The number keys by position (code:10 is 1), so this
-- works on every keyboard layout.
for i = 1, 10 do
    local key = "code:" .. (i + 9)
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = tostring(i) }))
end
-- Next and previous among the numbered workspaces that are in use.
hl.bind(mod .. " + TAB",         hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + SHIFT + TAB", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + mouse_down",  hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",    hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + S",           hl.dsp.workspace.toggle_special("scratchpad"))
hl.bind(mod .. " + ALT + S",     hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- A mistake in the user's file is noted in Hyprland's log and otherwise ignored.
local own = (os.getenv("HOME") or "") .. "/.config/hypr/odimac.lua"
local f = io.open(own)
if f then
    f:close()
    local ok, err = pcall(dofile, own)
    if not ok then print("odimac: " .. own .. ": " .. tostring(err)) end
end
