{
  flake.modules.homeManager.pi =
    { config, lib, ... }:
    {
      options.programs.pi.bashHighlight.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.programs.pi.toolDisplay.enable;
        defaultText = lib.literalExpression "config.programs.pi.toolDisplay.enable";
        description = "Syntax-highlight bash tool calls drawn by tool-display.";
      };

      config = lib.mkIf config.programs.pi.bashHighlight.enable {
        programs.pi.extensions.bash-highlight = ./bash-highlight.ts;
      };
    };
}
