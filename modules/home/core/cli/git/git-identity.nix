{
  flake.modules.homeManager.git-identity =
    { config, ... }:
    {
      age.secrets = {
        git-name.rekeyFile = ./git-name.age;
        git-email.rekeyFile = ./git-email.age;
      };

      # FRAGILE: $(cat ...) relies on zsh evaluating these before exec'ing fish.
      # If fish ever becomes the login shell directly, these will be literal strings.
      home.sessionVariables = {
        GIT_AUTHOR_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_AUTHOR_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
        GIT_COMMITTER_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_COMMITTER_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
      };
    };
}
