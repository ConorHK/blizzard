{
  flake.modules.homeManager.syncthing = {
    services.syncthing = {
      enable = true;
      settings = {
        # Add more in home files
        devices = {
          "phone".id = "XKQFBFW-377EUDV-HH72KPJ-HQMD2FT-3XCC6DE-6EDNETZ-YDQ4BI5-KZ7TLAW";
          # temp
          "server".id = "ACCG7I6-AV3WNQV-4IX26BM-7GL2KCR-W3PDMLC-PYTRVZI-2ROUULM-T4Y7IQD";
        };
        folders.share = {
          path = "~/share";
          devices = [
            "phone"
            "server"
          ];
        };

      };
    };
  };
}
