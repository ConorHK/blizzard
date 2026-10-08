{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      histerDataRules = config.flake.testSupport.histerDataRules;
    in
    {
      checks.hister = pkgs.testers.runNixOSTest {
        name = "hister";

        nodes.machine =
          { ... }:
          {
            users = {
              users = {
                hister = {
                  isSystemUser = true;
                  group = "hister";
                };
                containers = {
                  isSystemUser = true;
                  group = "containers";
                };
              };
              groups = {
                hister = { };
                containers = { };
              };
            };

            # Not the hister module itself: nginx, ACME and agenix are
            # beside the point. The rules under test are shared verbatim.
            systemd.tmpfiles.rules = histerDataRules "/storage/data/hister";
          };

        testScript = ''
          data = "/storage/data/hister"

          def as_containers(cmd):
              return machine.succeed(f"su containers -s /bin/sh -c '{cmd}'")

          def as_containers_denied(cmd):
              machine.fail(f"su containers -s /bin/sh -c '{cmd}'")

          # Recreate the broken state from leprechaun: shard dirs and
          # index files no group could read, plus a root-owned file
          # left behind by a manual sudo fix.
          machine.succeed(f"mkdir -p {data}/.config/hister/data/html/fb/5b")
          machine.succeed(f"chown -R hister:hister {data}")
          machine.succeed(f"chmod 700 {data}/.config/hister/data {data}/.config/hister/data/html {data}/.config/hister/data/html/fb {data}/.config/hister/data/html/fb/5b")
          machine.succeed(f"echo shard > {data}/.config/hister/data/html/fb/5b/shard.gz")
          machine.succeed(f"chmod 600 {data}/.config/hister/data/html/fb/5b/shard.gz")
          machine.succeed(f"echo index > {data}/.config/hister/index_en.db")
          machine.succeed(f"chmod 600 {data}/.config/hister/index_en.db")
          machine.succeed(f"echo db > {data}/.config/hister/db.sqlite3")
          machine.succeed(f"chown root:root {data}/.config/hister/db.sqlite3")

          as_containers_denied(f"cat {data}/.config/hister/index_en.db")

          machine.succeed("systemd-tmpfiles --create")

          with subtest("backup user reads every repaired file"):
              assert as_containers(f"cat {data}/.config/hister/data/html/fb/5b/shard.gz").strip() == "shard"
              assert as_containers(f"cat {data}/.config/hister/index_en.db").strip() == "index"
              assert as_containers(f"cat {data}/.config/hister/db.sqlite3").strip() == "db"

          with subtest("hister keeps ownership and gains no write bits"):
              # The old breakage: chowning content away from hister.
              assert machine.succeed(f"stat -c %U {data}/.config/hister/db.sqlite3").strip() == "hister"
              file_mode = int(machine.succeed(f"stat -c %a {data}/.config/hister/index_en.db"), 8)
              dir_mode = int(machine.succeed(f"stat -c %a {data}/.config/hister/data/html/fb/5b"), 8)
              assert file_mode & 0o040, oct(file_mode)
              assert dir_mode & 0o050 == 0o050, oct(dir_mode)
              assert not file_mode & 0o022, oct(file_mode)
              assert not dir_mode & 0o022, oct(dir_mode)

          with subtest("new files inherit the grant despite hostile umasks"):
              # Default ACLs override umask at creation time.
              machine.succeed(f"su hister -s /bin/sh -c 'umask 077; echo fresh > {data}/.config/hister/new.db'")
              assert as_containers(f"cat {data}/.config/hister/new.db").strip() == "fresh"

          with subtest("repair is idempotent and heals squashed masks"):
              # chmod collapses the ACL mask; a later run restores it.
              machine.succeed(f"chmod 600 {data}/.config/hister/new.db")
              as_containers_denied(f"cat {data}/.config/hister/new.db")
              machine.succeed("systemd-tmpfiles --create")
              machine.succeed("systemd-tmpfiles --create")
              assert as_containers(f"cat {data}/.config/hister/new.db").strip() == "fresh"
              assert as_containers(f"cat {data}/.config/hister/db.sqlite3").strip() == "db"
        '';
      };
    };
}
