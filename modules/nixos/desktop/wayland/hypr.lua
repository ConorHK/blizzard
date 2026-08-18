-- Loaded and placeholder-substituted by hyprland.nix; edit Hyprland config here.

hl.config({
    general = {
        gaps_in  = 0,
        gaps_out = 0,

        border_size      = 2,
        resize_on_border = true,

        col = {
            active_border   = "0xFFAF875F",
            inactive_border = "rgb(878787)",
        },
    },

    decoration = {
        shadow = {
            color = "rgba(1c1c1c99)",
        },
    },

    input = {
        follow_mouse = 2,

        repeat_delay = 400,
        repeat_rate  = 30,

        touchpad = {
            clickfinger_behavior = true,
            drag_lock            = true,
            natural_scroll       = false,
            scroll_factor        = 0.7,
        },
    },

    misc = {
        animate_manual_resizes     = true,
        initial_workspace_tracking = 2,

        disable_hyprland_logo    = true,
        disable_splash_rendering = true,

        key_press_enables_dpms  = true,
        mouse_move_enables_dpms = true,

        background_color = "rgb(1c1c1c)",
    },

    cursor = {
        hide_on_key_press = true,
        inactive_timeout  = 10,
        no_warps          = true,
    },

    dwindle = {
        preserve_split = true,
        smart_resizing = false,
    },

    ecosystem = {
        no_update_news      = true,
        no_donation_nag     = true,
        enforce_permissions = false,
    },

    group = {
        col = {
            border_active        = "rgb(878787)",
            border_inactive      = "rgb(878787)",
            border_locked_active = "rgb(87afaf)",
        },

        groupbar = {
            text_color = "rgb(dfdfaf)",
            col = {
                active   = "rgb(878787)",
                inactive = "rgb(878787)",
            },
        },
    },

    xwayland = {
        enabled            = true,
        force_zero_scaling = true,
    },

    animations = {
        enabled = true,
    },
})

hl.curve("material_decelerate", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })

hl.animation({ leaf = "border",     enabled = true, speed = 2, bezier = "material_decelerate" })
hl.animation({ leaf = "fade",       enabled = true, speed = 2, bezier = "material_decelerate" })
hl.animation({ leaf = "layers",     enabled = true, speed = 2, bezier = "default", style = "slide" })
hl.animation({ leaf = "windows",    enabled = true, speed = 1, bezier = "default", style = "gnomed" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "material_decelerate", style = "slidevert" })

hl.gesture({ fingers = 3, direction = "vertical", action = "workspace" })

hl.layer_rule({ match = { namespace = "selection" }, no_anim = true })

hl.window_rule({ match = { class = "xdg-desktop-portal-gtk", title = "^(Open.*Files?|Save.*Files?|All Files|Save)" }, float  = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk", title = "^(Open.*Files?|Save.*Files?|All Files|Save)" }, center = true })
hl.window_rule({ match = { title = "^(File Upload)" }, float  = true })
hl.window_rule({ match = { title = "^(File Upload)" }, center = true })
hl.window_rule({ match = { class = "^(firefox)$", title = "^(Picture-in-Picture)$" }, float = true })
hl.window_rule({ match = { class = "^(steam)$", initial_title = "^(Friends List)$" }, float = true })
hl.window_rule({ match = { class = "com.saivert.pwvucontrol" }, float  = true })
hl.window_rule({ match = { class = "com.saivert.pwvucontrol" }, center = true })

hl.bind("SUPER + P", hl.dsp.exec_cmd("@screenshot@"))
hl.bind("SUPER + R", hl.dsp.exec_cmd("@resize@"))

hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + S", hl.dsp.window.float({ action = "toggle" }))

local dirs = {
    h = "left", l = "right", k = "up", j = "down",
    Left = "left", Right = "right", Up = "up", Down = "down",
}
for key, d in pairs(dirs) do
    hl.bind("SUPER + " .. key,         hl.dsp.focus({ direction = d }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.swap({ direction = d }))
end

for i = 1, 10 do
    local key = i % 10
    hl.bind("SUPER + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

hl.bind("SUPER + u",         hl.dsp.workspace.toggle_special())
hl.bind("SUPER + SHIFT + u", hl.dsp.window.move({ workspace = "special" }))

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprland-session.service")
    hl.exec_cmd("systemctl --user start hyprpaper")
    hl.exec_cmd("@floatExtensions@")
end)
