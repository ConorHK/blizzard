{ inputs, ... }:
{
  hyprland.lua.firefox = ''
    hl.bind("SUPER + SHIFT + F", hl.dsp.exec_cmd("uwsm app -- firefox"))
  '';

  flake.modules.nixos.desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.stylix) fonts;
      px = points: builtins.floor ((points * 4.0 / 3.0) + 0.5);

      policies = {
        AutofillAddressEnabled = false;
        AutofillCreditCardEnabled = false;
        DefaultDownloadDirectory = "\${home}/dl";
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

            # Extensions where the gecko ID is also the AMO slug (email-style or matching slug)
            extensions = [
              "9350bc42-47fb-4598-ae0f-825e3dd9ceba" # enable-right-click
              "addon@darkreader.org"
              "skipredirect@sblask"
              "idcac-pub@guus.ninja"
              "uBlock0@raymondhill.net"
            ];
          in
          (builtins.listToAttrs (map mkFirefoxExtension extensions))
          // {
            # Extensions where the gecko UUID differs from the AMO slug
            "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi";
            };
            "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
            };
            "{3c078156-979c-498b-8990-85f7987dd929}" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/sidebery/latest.xpi";
            };
            "{f0bda7ce-0cda-42dc-9ea8-126b20fed280}" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/hister/latest.xpi";
            };
          };
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

      # user.js lines, applied at every start.
      preferences = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "general.autoScroll" = true;
        "browser.ctrlTab.sortByRecentlyUsed" = true;
        "browser.fullscreen.autohide" = false;
        "browser.nova.enabled" = false;
        "browser.tabs.closeWindowWithLastTab" = true;
        # Old sidebar has no launcher; userChrome hides its header.
        "sidebar.revamp" = false;

        # textfox needs these.
        "svg.context-properties.content.enabled" = true;
        "layout.css.has-selector.enabled" = true;

        "font.name.monospace.x-western" = fonts.monospace.name;
        "font.name.sans-serif.x-western" = fonts.sansSerif.name;
        "font.name.serif.x-western" = fonts.serif.name;
        "font.size.monospace.x-western" = px fonts.sizes.terminal;
        "font.size.variable.x-western" = px fonts.sizes.applications;
      };

      chromeEntries = lib.unique (
        lib.attrNames (builtins.readDir "${inputs.textfox}/chrome") ++ [ "config.css" ]
      );

      # textfox's stylesheets, with its own userChrome.css followed by ours.
      chrome = pkgs.runCommandLocal "firefox-chrome" { } ''
        cp --recursive ${inputs.textfox}/chrome $out
        chmod --recursive u+w $out
        cat ${./userChrome.css} >> $out/userChrome.css
        cp ${pkgs.writeText "config.css" config.textfox.configCss} $out/config.css
      '';

      firefox =
        (pkgs.wrapFirefox pkgs.firefox-unwrapped {
          extraPolicies = policies;
          extraPrefs = lib.concatMapAttrsStringSep "" (
            name: value: "pref(${builtins.toJSON name}, ${builtins.toJSON value});\n"
          ) preferences;
          # Vicinae's browser extension talks to this host.
          nativeMessagingHosts = [
            (pkgs.writeTextDir "lib/mozilla/native-messaging-hosts/com.vicinae.vicinae.json" (
              builtins.toJSON {
                name = "com.vicinae.vicinae";
                description = "Vicinae Native Messaging Host";
                path = "${pkgs.vicinae}/libexec/vicinae/vicinae-browser-link";
                type = "stdio";
                allowed_extensions = [ "firefox@vicinae.com" ];
              }
            ))
          ];
        }).overrideAttrs
          (old: {
            makeWrapperArgs = old.makeWrapperArgs ++ [
              # Hyprland pins every window of a tokened process.
              "--unset"
              "HL_INITIAL_WORKSPACE_TOKEN"
              # Nothing writes profiles.ini any more, so the profile is named here.
              "--add-flags"
              "--profile \"\$HOME/.mozilla/firefox/primary\""
            ];
          });
    in
    {
      # Only the options: they turn the settings below into textfox's config.css.
      imports = [ "${inputs.textfox}/nix/modules/options.nix" ];
      textfox.config = {
        displayNavButtons = true;
        displaySidebarTools = false;
      };

      environment = {
        systemPackages = [ firefox ];
        sessionVariables.BROWSER = "firefox";
        etc."firefox/chrome".source = chrome;
      };

      # Each stylesheet is linked on its own, so a chrome directory that holds other files
      # still gets them. L never replaces a file that is already there.
      systemd.user.tmpfiles.rules = [
        "d %h/.mozilla/firefox/primary/chrome 0755 - - -"
      ]
      ++ map (
        name: "L %h/.mozilla/firefox/primary/chrome/${name} - - - - /etc/firefox/chrome/${name}"
      ) chromeEntries;
    };
}
