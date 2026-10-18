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
      lib.attrNames (
        lib.filterAttrs (_: vhost: !vhost.default) (nixos.config.services.nginx.virtualHosts or { })
      )
    );

  checksOn =
    host: nixos:
    let
      vhosts = publishedOn nixos;
    in
    lib.filter (
      check:
      lib.hasInfix "://${host}:" check.url
      || lib.hasInfix "://${host}/" check.url
      || lib.hasSuffix "://${host}" check.url
      || lib.any (vhost: lib.hasInfix vhost check.url) vhosts
    ) checks;

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
        window = nixos.config.system.autoUpgrade.rebootWindow;
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
