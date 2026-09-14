{
  flake.modules.homeManager.zai =
    { config, ... }:
    {
      age.secrets.zai-api-key.rekeyFile = ./zai-api-key.age;

      # Coding plan quota needs the coding-only endpoint.
      programs.pi.models.providers.zai = {
        baseUrl = "https://api.z.ai/api/coding/paas/v4";
        api = "openai-completions";
        apiKey = "!cat ${config.age.secrets.zai-api-key.path}";
        # GLM rejects the "developer" role and "store" field.
        compat = {
          supportsDeveloperRole = false;
          supportsStore = false;
        };
        models = [
          { id = "glm-5.3"; }
          { id = "glm-5.3-flash"; }
          { id = "glm-5.2"; }
        ];
      };
    };
}
