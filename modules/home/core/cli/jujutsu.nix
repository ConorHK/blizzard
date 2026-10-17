{
  flake.modules.homeManager.jujutsu = {
    programs = {
      jujutsu.enable = true;
      difftastic.jujutsu.enable = true;
    };
  };
}
