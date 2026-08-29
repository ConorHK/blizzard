{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.clip = pkgs.testers.runNixOSTest {
        name = "clip";

        nodes = {
          # eth1 stands in for wg0/tailscale0, the only interfaces leprechaun trusts.
          mailbox = {
            imports = with config.flake.modules.nixos; [
              clip
              clip-server
            ];
            networking.firewall.trustedInterfaces = [ "eth1" ];
          };

          # Same service behind the stock firewall: proves the port is never opened.
          sealed = {
            imports = [ config.flake.modules.nixos.clip-server ];
            environment.systemPackages = [ pkgs.curl ];
          };

          phone = {
            imports = [ config.flake.modules.nixos.clip ];
            environment.systemPackages = [ pkgs.curl ];
          };
        };

        testScript = ''
          URL = "http://mailbox:7391"


          def clip(args="", stdin=None):
              cmd = f"CLIP_URL={URL} clip {args}"
              return f"{stdin} | {cmd}" if stdin else cmd


          # curl rewrites ".." client-side, so traversal needs --path-as-is.
          def status(node, path, extra=""):
              return node.succeed(
                  "curl -sS --path-as-is -o /dev/null "
                  f"-w '%{{http_code}}' {extra} {URL}{path}"
              ).strip()


          start_all()
          mailbox.wait_for_unit("clip.service")
          mailbox.wait_for_open_port(7391)
          sealed.wait_for_unit("clip.service")
          phone.wait_for_unit("multi-user.target")

          # A bare curl 404 here reads like a network fault, not an empty slot.
          with subtest("an empty slot says so in words"):
              out = phone.fail(clip() + " 2>&1")
              assert "is empty" in out, out
              assert "404" not in out, out

          with subtest("phone writes, mailbox reads"):
              phone.succeed(clip(stdin="echo ssh-ed25519-AAAA"))
              assert mailbox.succeed(clip()).strip() == "ssh-ed25519-AAAA"

          with subtest("mailbox writes, phone reads"):
              mailbox.succeed(clip("note", stdin="echo reply-from-pc"))
              assert phone.succeed(clip("note")).strip() == "reply-from-pc"

          with subtest("slots do not clobber each other"):
              assert phone.succeed(clip()).strip() == "ssh-ed25519-AAAA"

          with subtest("a file redirect writes"):
              phone.succeed("echo from-a-file > /tmp/f")
              phone.succeed(clip("fromfile") + " < /tmp/f")
              assert phone.succeed(clip("fromfile")).strip() == "from-a-file"

          # Regression: `[ -t 0 ]` counted this as a write and silently wiped the slot.
          with subtest("a stray < /dev/null reads instead of wiping"):
              assert phone.succeed(clip() + " < /dev/null").strip() == "ssh-ed25519-AAAA"
              assert phone.succeed(clip()).strip() == "ssh-ed25519-AAAA"

          with subtest("multi-byte utf-8 survives byte for byte"):
              phone.succeed(clip("uni", stdin="echo café"))
              dump = phone.succeed(clip("uni") + " | od -An -v -tx1 | tr -d ' \n'")
              assert dump.strip() == "636166c3a90a", dump

          with subtest("a slot name cannot escape the state directory"):
              # Anchor the paths below, so the escape assertions are not vacuous.
              mailbox.succeed("test -d /var/lib/private/clip")
              assert status(phone, "/default") == "200"

              # One level up is a directory the service can write, so nothing
              # but the name check stops this: a 400 proves the check ran.
              assert status(phone, "/../escaped", "-T /etc/hostname") == "400"
              assert status(phone, "/%2e%2e%2fescaped", "-T /etc/hostname") == "400"
              assert status(phone, "/../../etc/passwd") == "400"
              mailbox.succeed("test ! -e /var/lib/private/escaped")

          # A shell that mangles the default-slot expansion must not silently
          # get its own slot: rejecting it is what surfaces the broken client.
          with subtest("a mangled slot name is rejected, not quietly created"):
              assert status(phone, "/1:-default") == "400"
              assert status(phone, "/1:-default", "-T /etc/hostname") == "400"
              mailbox.succeed("test ! -e '/var/lib/clip/1:-default'")

          with subtest("a body over 1 MiB is refused"):
              phone.fail(clip("big", stdin="yes | head -c 2097152"))
              phone.fail(clip("big"))

          with subtest("slots survive a service restart"):
              mailbox.succeed("systemctl restart clip.service")
              mailbox.wait_for_open_port(7391)
              assert phone.succeed(clip()).strip() == "ssh-ed25519-AAAA"

          # A traceback per dropped keep-alive socket would bury a real fault.
          with subtest("routine traffic leaves no traceback in the journal"):
              journal = mailbox.succeed("journalctl -u clip.service --no-pager")
              assert "Traceback" not in journal, journal

          with subtest("the port is unreachable where no interface is trusted"):
              # Listening locally, so the failure from phone is the firewall, not a dead unit.
              sealed.succeed("curl -sS --max-time 5 -o /dev/null http://127.0.0.1:7391/")
              phone.fail("curl -sS --max-time 5 -o /dev/null http://sealed:7391/")
        '';
      };
    };
}
