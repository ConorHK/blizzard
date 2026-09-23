let
  markers = builtins.fromJSON ''
    { "empty": "\u25a2", "noDescription": "\u2190" }
  '';
in
{
  flake.modules.homeManager.jujutsu = {
    programs.jujutsu = {
      enable = true;
      settings = {
        templates.log = "simple_log";
        template-aliases = {
          empty_commit_marker = "label('empty', '${markers.empty}')";
          simple_log = ''
            separate(" ",
              pad_end(
                4,
                separate("/",
                  self.change_id().shortest(),
                  if(self.divergent() || self.hidden(), self.change_offset())
                )
              ),
              if(self.immutable(), "L ", "  ") ++ " ",
              if(self.empty(), empty_commit_marker),
              if(self.description(), self.description().first_line(), if(self.empty(), "", label('no_description', '${markers.noDescription}'))),
              self.bookmarks()
            )
          '';
        };
      };
    };
  };
}
