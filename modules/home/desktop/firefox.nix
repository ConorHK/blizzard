{
  flake.modules.homeManager.firefox =
    { inputs, ... }:

    {
      imports = [
        inputs.textfox.homeManagerModules.default
      ];

      wayland.windowManager.hyprland.settings.bind = [
        "SUPER_SHIFT, F, exec, uwsm app -- firefox"
      ];

      home.sessionVariables.BROWSER = "firefox";
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
            settings = {
              "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
              "browser.ctrlTab.sortByRecentlyUsed" = true;
              "browser.fullscreen.autohide" = false;
            };
            userChrome = ''
              /* Alduin Theme */
              :root {
                --alduin-bg: #1c1c1c;
                --alduin-fg: #dfdfaf;
                --alduin-black-soft: #262626;
                --alduin-red: #8b5f61;
                --alduin-green: #87875f;
                --alduin-yellow: #fed975;
                --alduin-blue: #87afaf;
                --alduin-magenta: #af8787;
                --alduin-orange: #d69f74;
                --alduin-white: #f4f4f4;
                --alduin-gray: #444444;
              }

              /* Hide tabs (existing) */
              #TabsToolbar { visibility: collapse !important; }

              /* Hide sidebar header (existing) */
              #sidebar-header { display: none !important; }

              /* Alduin UI overrides */
              #navigator-toolbox { background-color: var(--alduin-bg) !important; color: var(--alduin-fg) !important; }
              #urlbar { background-color: var(--alduin-black-soft) !important; color: var(--alduin-fg) !important; border-color: var(--alduin-blue) !important; }
              #urlbar-input { color: var(--alduin-fg) !important; }
              #nav-bar { background-color: var(--alduin-bg) !important; }
              #sidebar { background-color: var(--alduin-black-soft) !important; color: var(--alduin-fg) !important; }
              .tab-background { background-color: var(--alduin-bg) !important; }
              menubar-items, toolbarbutton { color: var(--alduin-fg) !important; }
              #sidebar-splitter { border-color: var(--alduin-black-soft) !important; background-color: var(--alduin-black-soft) !important; }
              /* Textfox compatibility: subtle accents */
              toolbarbutton:hover { background-color: var(--alduin-black-soft) !important; }
              toolbarbutton[checked="true"] { background-color: var(--alduin-blue) !important; color: var(--alduin-bg) !important; }
            '';

          };
        };
      };

      textfox = {
        enable = true;
        profiles = [ "primary" ];
        config = {
          displayNavButtons = true;
        };
      };
    };
}
