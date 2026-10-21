{
  nixpkgs.allowedUnfreePackages = [ "obsidian" ];

  flake.modules.homeManager.ogham =
    { lib, pkgs, ... }:
    let
      vault = "ogham";

      # Release assets; manifestId avoids IFD.
      mkPlugin =
        {
          id,
          repo,
          version,
          hashes,
        }:
        pkgs.linkFarm "obsidian-plugin-${id}-${version}" (
          lib.mapAttrs (
            file: hash:
            pkgs.fetchurl {
              url = "https://github.com/${repo}/releases/download/${version}/${file}";
              inherit hash;
            }
          ) hashes
        )
        // {
          manifestId = id;
        };

      plugins = {
        templater = mkPlugin {
          id = "templater-obsidian";
          repo = "SilentVoid13/Templater";
          version = "2.26.0";
          hashes = {
            "main.js" = "sha256-Cs1Fz9s6czfivvURaZvB+BncZGRa00gN8zV51C0ty6o=";
            "manifest.json" = "sha256-kcn6hRAIL/+gs9AiqsSYbjs5IpWxEm6Efq1+1yiRabg=";
            "styles.css" = "sha256-Z6bdLR1t7coSh8M0yohOxBlkM/ccpHOIoL0+rBTPi18=";
          };
        };
        tasks = mkPlugin {
          id = "obsidian-tasks-plugin";
          repo = "obsidian-tasks-group/obsidian-tasks";
          version = "8.6.0";
          hashes = {
            "main.js" = "sha256-UA+BBtBd20g7v+wTXKx5SAIr9rpzhtGFGyj00IeGbo8=";
            "manifest.json" = "sha256-LvyI356XMkc2DUhrQgeRwmbIgkUWkZMDuUjQGS4VkSc=";
            "styles.css" = "sha256-1w2OvUH8I7/V1Zhzsak+2VVLFUVGo+Y3vU4ELmLRzyM=";
          };
        };
        calendar = mkPlugin {
          id = "calendar";
          repo = "liamcain/obsidian-calendar-plugin";
          version = "1.5.10";
          hashes = {
            "main.js" = "sha256-f7M56c+f2+WoAforirhbNmtbN3f70ZPLyHKLwncR0SU=";
            "manifest.json" = "sha256-8+lYEzhkhRK6oS1bRYSQ9/02eRj3vba9hhcc5Xvn0Is=";
          };
        };
        git = mkPlugin {
          id = "obsidian-git";
          repo = "Vinzent03/obsidian-git";
          version = "2.42.0";
          hashes = {
            "main.js" = "sha256-SW2xSLzqQWn0VeI0uwLwj4xQwxfArVr947J8CQTa8TM=";
            "manifest.json" = "sha256-etmOjM4VfphGtHlBxqfLmwIrydXG0ReCKQ56ehZLRw0=";
            "styles.css" = "sha256-8wrSykL+/jtwTFSPd0fShcIDj6TOkGAeaP5v1mBJQFI=";
          };
        };
      };

      initVault = pkgs.writeShellApplication {
        name = "ogham-init";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
        ];
        text = ''
          vault=$1
          mkdir -p "$vault"/{Daily,People,Topics,Meetings,Clippings,Inbox,Attachments,Templates}
          install -m 644 ${./templates}/*.md "$vault/Templates/"
          if [ ! -e "$vault/Home.md" ]; then
            install -m 644 ${./Home.md} "$vault/Home.md"
          fi
          if [ ! -d "$vault/.git" ]; then
            git -C "$vault" init -q -b main
          fi
          # Git ignores a symlinked .gitignore.
          mkdir -p "$vault/.git/info"
          printf '%s\n' .obsidian/ .trash/ .DS_Store >"$vault/.git/info/exclude"
        '';
      };

      folderTemplate = folder: name: {
        inherit folder;
        template = "Templates/${name}.md";
      };
    in
    {
      programs.obsidian = {
        enable = true;
        vaults.${vault}.settings = {
          app = {
            alwaysUpdateLinks = true;
            attachmentFolderPath = "Attachments";
            newFileLocation = "folder";
            newFileFolderPath = "Inbox";
          };

          corePlugins = [
            "backlink"
            "bases"
            "bookmarks"
            "command-palette"
            "editor-status"
            "file-explorer"
            "file-recovery"
            "global-search"
            "graph"
            "outgoing-link"
            "outline"
            "page-preview"
            "properties"
            "switcher"
            "tag-pane"
            "word-count"
            {
              name = "daily-notes";
              settings = {
                folder = "Daily";
                format = "YYYY-MM-DD";
                template = "Templates/Daily";
                autorun = true;
              };
            }
          ];

          communityPlugins = [
            plugins.tasks
            plugins.calendar
            {
              pkg = plugins.templater;
              settings = {
                data_version = 2;
                templates_folder = "Templates";
                trigger_on_file_creation_mode = "folder";
                auto_jump_to_cursor = true;
                folder_templates = [
                  (folderTemplate "People" "Person")
                  (folderTemplate "Topics" "Topic")
                  (folderTemplate "Meetings" "Meeting")
                ];
              };
            }
            {
              pkg = plugins.git;
              settings = {
                autoSaveInterval = 10;
                autoPullOnBoot = false;
                disablePush = true;
                autoCommitMessage = "vault: {{date}}";
              };
            }
          ];
        };
      };

      home.activation.ogham = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe initVault} "$HOME/${vault}"
      '';
    };
}
