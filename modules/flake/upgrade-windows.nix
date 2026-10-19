{ lib, config, ... }:
let
  hosts = config.flake.nixosConfigurations;
  checks = lib.attrValues config.flake.monitoringChecks;

  # Boot time after a reboot at the window's end.
  bootMargin = 10;

  minutes =
    clock:
    let
      parts = map lib.toIntBase10 (lib.splitString ":" clock);
    in
    lib.elemAt parts 0 * 60 + lib.elemAt parts 1;

  durationMinutes =
    duration:
    let
      parsed = builtins.match "(([0-9]+)h)?(([0-9]+)m)?" duration;
      part =
        index:
        if parsed == null || lib.elemAt parsed index == null then
          0
        else
          lib.toIntBase10 (lib.elemAt parsed index);
    in
    if parsed == null || duration == "" then
      throw "upgrade-windows: cannot parse duration ${duration}"
    else
      part 1 * 60 + part 3;

  # Daily windows only; `every` limits the days.
  covers =
    zone: from: to: window:
    let
      start = minutes window.start;
    in
    (window.every or [ ]) == [ ]
    && (window.timezone or "Europe/Dublin") == zone
    && start <= from
    && start + durationMinutes window.duration >= to;

  gatusHosts = lib.filterAttrs (_: nixos: nixos.config.services.gatus.enable or false) hosts;
  globalWindows = lib.concatMap (
    nixos: lib.toList (nixos.config.services.gatus.settings.maintenance or [ ])
  ) (lib.attrValues gatusHosts);

  publishedOn =
    nixos:
    lib.filter (lib.hasInfix ".") (
      lib.concatLists (
        lib.mapAttrsToList (name: vhost: lib.optionals (!vhost.default) ([ name ] ++ vhost.serverAliases)) (
          nixos.config.services.nginx.virtualHosts or { }
        )
      )
    );

  urlHost =
    url:
    let
      parsed = builtins.match "[a-z][a-z0-9+.-]*://([^/:?#]+).*" url;
    in
    if parsed == null then null else lib.head parsed;

  checksOn =
    host: nixos:
    let
      names = [ host ] ++ publishedOn nixos;
    in
    lib.filter (check: lib.elem (urlHost check.url) names) checks;

  # gatus-watch covers the gatus host's own reboot.
  rebooting = lib.filterAttrs (
    host: nixos:
    nixos.config.system.autoUpgrade.enable
    && nixos.config.system.autoUpgrade.allowReboot
    && !(gatusHosts ? ${host})
  ) hosts;

  unsilenced = lib.concatLists (
    lib.mapAttrsToList (
      host: nixos:
      let
        # No window: reboots at any time.
        window = lib.defaultTo {
          lower = "00:00";
          upper = "24:00";
        } nixos.config.system.autoUpgrade.rebootWindow;
        zone = nixos.config.time.timeZone;
        from = minutes window.lower;
        to = minutes window.upper + bootMargin;
        silenced = check: lib.any (covers zone from to) (globalWindows ++ check.maintenanceWindows);
      in
      map (check: "${host}: ${check.name} pages during ${window.lower}-${window.upper}") (
        lib.filter (check: !silenced check) (checksOn host nixos)
      )
    ) rebooting
  );
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.upgrade-windows = pkgs.runCommand "upgrade-windows" { } (
        if unsilenced == [ ] then
          "touch $out"
        else
          ''
            echo "No maintenance window covers these reboots:"
            ${lib.concatMapStrings (line: "echo ${lib.escapeShellArg "  ${line}"}\n") unsilenced}
            exit 1
          ''
      );
    };
}
