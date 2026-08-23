-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- Android Emulator window rules (floating, full opacity, preserve aspect ratio)
o.window("class:^(Emulator)$", { float = true, tag = "-default-opacity", opacity = "1 1" })
o.window("class:^(qemu-system-.*)$", { float = true, tag = "-default-opacity", opacity = "1 1" })

-- Added by hyprmoncfg: its generated monitor rules load last, so nothing before this can override the applied layout.
local hyprmoncfg_file = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"
local f = io.open(hyprmoncfg_file, "r")
if f then
  f:close()
  dofile(hyprmoncfg_file)
end
