-- The desktop of the OpenDisplay iMac appliance (Ctrl+Alt+3): Hyprland with a
-- Quickshell bar, on a virtual terminal of its own beside the kiosk session.
-- Started by odimac-desktop.service through /usr/lib/odimac/desktop-session.
-- Your own settings go in ~/.config/hypr/odimac.lua, which is read last and
-- can change anything set here.

local mode     = "systemd-cat -t odimac-mode /usr/lib/odimac/mode "
local terminal = "foot"
local menu     = "fuzzel"
local mod      = "SUPER" -- the Command key on an Apple keyboard

-- Retina, as in the kiosk session: a 2560x1440 desktop on the 5K panel.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 })

hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        col = {
            active_border   = "rgba(8aadf4ee)",
            inactive_border = "rgba(494d64aa)",
        },
        layout = "dwindle",
    },
    decoration = {
        rounding = 8,
        -- The 2017 Radeon also decodes the Mac's stream in the background.
        blur   = { enabled = false },
        shadow = { enabled = false },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    input = { kb_layout = "us", follow_mouse = 1 },
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = "rgb(1e2030)",
        -- The service starts Hyprland itself, without start-hyprland.
        disable_watchdog_warning = true,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("qs -p /usr/share/odimac/quickshell")
    hl.exec_cmd(mode .. "watch")
    -- The 5K driver can bring the panel up with half the picture stretched
    -- across it; turning it off and on once corrects that (PANEL_POWER_CYCLE).
    if os.getenv("ODIMAC_PANEL_CYCLE") == "1" then
        hl.exec_cmd([[sh -c "sleep 3; hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'; sleep 2; hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'"]])
    end
end)

-- The other two environments. Ctrl+Alt+3 is this one.
hl.bind("CTRL + ALT + 1", hl.dsp.exec_cmd(mode .. "display"), { locked = true })
hl.bind("CTRL + ALT + 2", hl.dsp.exec_cmd(mode .. "game"),    { locked = true })
hl.bind("CTRL + ALT + 4", hl.dsp.exec_cmd(mode .. "shell"),   { locked = true })

hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Space",  hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + Q",      hl.dsp.window.close())
hl.bind(mod .. " + F",      hl.dsp.window.fullscreen())
hl.bind(mod .. " + V",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + J",      hl.dsp.layout("togglesplit"))
-- Log out: closes every program on the desktop and returns to the Mac's display.
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())

for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mod .. " + " .. dir,            hl.dsp.focus({ direction = dir }))
    hl.bind(mod .. " + SHIFT + " .. dir,    hl.dsp.window.move({ direction = dir }))
end
for i = 1, 9 do
    hl.bind(mod .. " + " .. i,              hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i,      hl.dsp.window.move({ workspace = i }))
end
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273",  hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -q set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q -n 2 set 5%-"), { locked = true, repeating = true })

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
