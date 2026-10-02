{
  flake.modules.homeManager.git-identity =
    { config, ... }:
    {
      age.secrets = {
        git-name.rekeyFile = ./git-name.age;
        git-email.rekeyFile = ./git-email.age;
      };

      home.sessionVariables = {
        GIT_AUTHOR_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_AUTHOR_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
        GIT_COMMITTER_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_COMMITTER_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
      };
    };
}
