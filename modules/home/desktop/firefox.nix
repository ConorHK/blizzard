{
  flake.modules.homeManager.firefox =
    { inputs, ... }:

    {
      imports = [
        inputs.textfox.homeManagerModules.default
      ];

      wayland.windowManager.hyprland.settings.bind = [
        "SUPER_SHIFT, F, exec, firefox"
      ];

      home.sessionVariables.BROWSER = "firefox";
      stylix.targets.firefox.profileNames = [ "primary" ];
      programs.firefox = {
        enable = true;
        policies = {
          AutofillAddressEnabled = false;
          AutofillCreditCardEnabled = false;
          DefaultDownloadDirectory = "~/dl";
          DisableBuiltinPDFViewer = true;
          DisableMasterPasswordCreation = true;
          DisablePocket = true;
          DisableSetDesktopBackground = true;
          DisableTelemetry = true;
          DontCheckDefaultBrowser = true;
          ExtensionSettings =
            let
              mkFirefoxExtension = extensionId: {
                name = extensionId;
                value = {
                  installation_mode = "force_installed";
                  install_url = "https://addons.mozilla.org/firefox/downloads/latest/${extensionId}/latest.xpi";
                };
              };

              extensions = [
                "d7742d87-e61d-4b78-b8a1-b469842139fa" # vimium
                "vimium-ff"
                "9350bc42-47fb-4598-ae0f-825e3dd9ceba" # enable-right-click
                "bitwarden-password-manager"
                "addon@darkreader.org"
                "sidebery"
                "skipredirect@sblask"
                "idcac-pub@guus.ninja"
              ];
            in
            builtins.listToAttrs (map mkFirefoxExtension extensions);
          FirefoxHome = {
            SponsoredTopSites = false;
            Highlights = false;
            Pocket = false;
            SponsoredPocket = false;
            Snippets = false;
          };
          FirefoxSuggest = {
            WebSuggestions = false;
            SponsoredSuggestions = false;
            ImproveSuggestions = false;
            Locked = true;
          };
          HttpsOnlyMode = "enabled";
          NoDefaultBookmarks = true;
          OfferToSaveLogins = false;
          PasswordManagerEnabled = false;
          PromptForDownloadLocation = true;
          SearchSuggestEnabled = false;
        };
        profiles = {
          primary = {
            id = 0;
            settings."toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            settings."browser.ctrlTab.sortByRecentlyUsed" = true;
            settings."browser.tabs.closeWindowWithLastTab" = false;
            userChrome = ''
              #TabsToolbar
              {
                  visibility: collapse;
              }
              #sidebar-header {
                display: none;
              }
            '';

          };
        };
      };

      textfox = {
        enable = true;
        profile = "primary";
        useLegacyExtensions = false;
        config = {
          displayNavButtons = true;
        };
      };
    };
}
