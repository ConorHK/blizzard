# TODO: Move git-url to its own package so nvim and blizzard can depend on it without circular dependencies
{ lib, ... }:
{
  flake.modules.homeManager.core =
    {
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.git-url;

      defaultUrlBuilder = pkgs.writeShellScript "git-url-builder" ''
        remote_url="$1" branch="$2" file="$3" line="$4"

        if echo "$remote_url" | grep -q "github\.com"; then
          path=$(echo "$remote_url" | sed -E 's|.*github\.com[:/]||; s|\.git$||')
          base="https://github.com/''${path}"
          if [ -n "$file" ]; then
            url="''${base}/blob/''${branch}/''${file}"
            [ -n "$line" ] && url="''${url}#L''${line}"
          else
            url="$base"
          fi
        elif echo "$remote_url" | grep -q "gitlab"; then
          path=$(echo "$remote_url" | sed -E 's|.*gitlab[^/]*[:/]||; s|\.git$||')
          base="https://gitlab.com/''${path}"
          if [ -n "$file" ]; then
            url="''${base}/-/blob/''${branch}/''${file}"
            [ -n "$line" ] && url="''${url}#L''${line}"
          else
            url="$base"
          fi
        else
          echo "Unknown remote: $remote_url" >&2
          exit 1
        fi

        echo "$url"
      '';

      git-url = pkgs.writeShellScriptBin "git-url" ''
        set -euo pipefail

        remote_url=$(git remote get-url origin 2>/dev/null) || {
          echo "Not a git repository or no origin remote" >&2
          exit 1
        }

        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="main"

        file="" line=""
        if [ $# -ge 1 ]; then
          repo_root=$(git rev-parse --show-toplevel)
          file=$(realpath --relative-to="$repo_root" "$1" 2>/dev/null || echo "$1")
        fi
        [ $# -ge 2 ] && line="$2"

        url=$(${cfg.urlBuilder} "$remote_url" "$branch" "$file" "$line")
        echo "$url"
      '';
    in
    {
      options.programs.git-url.urlBuilder = lib.mkOption {
        type = lib.types.path;
        default = defaultUrlBuilder;
        description = "Script that takes (remote_url, branch, file, line) and outputs a URL";
      };

      config.home.packages = [ git-url ];
    };
}
