{
  hyprland.lua.swayosd = ''
    local osd = "swayosd-client --monitor \"$(hyprctl monitors -j | jq -r '.[] | select(.focused == true).name')\""

    hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd(osd .. " --output-volume raise"),       { locked = true, repeating = true })
    hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd(osd .. " --output-volume lower"),       { locked = true, repeating = true })
    hl.bind("Prior",                 hl.dsp.exec_cmd(osd .. " --output-volume raise"),       { locked = true, repeating = true })
    hl.bind("Next",                  hl.dsp.exec_cmd(osd .. " --output-volume lower"),       { locked = true, repeating = true })
    hl.bind("XF86AudioMute",         hl.dsp.exec_cmd(osd .. " --output-volume mute-toggle"), { locked = true, repeating = true })
    hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd(osd .. " --input-volume mute-toggle"),  { locked = true, repeating = true })
    hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(osd .. " --brightness raise"),          { locked = true, repeating = true })
    hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(osd .. " --brightness lower"),          { locked = true, repeating = true })

    hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(osd .. " --playerctl next"),       { locked = true })
    hl.bind("XF86AudioPause", hl.dsp.exec_cmd(osd .. " --playerctl play-pause"), { locked = true })
    hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(osd .. " --playerctl play-pause"), { locked = true })
    hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(osd .. " --playerctl previous"),   { locked = true })
  '';

  flake.modules.homeManager.swayosd = {
    services.swayosd.enable = true;
  };
}
