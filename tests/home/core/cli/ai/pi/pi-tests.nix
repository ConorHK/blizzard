{ config, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      homes = lib.filterAttrs (
        _: home:
        home.pkgs.stdenv.hostPlatform.system == system && home.config.programs.pi.settings ? packages
      ) config.flake.homeConfigurations;

      # Missing manifest entries load silently.
      driver = pkgs.writeText "pi-load.mjs" ''
        import { spawn } from "node:child_process";
        import { existsSync, globSync, readFileSync, readdirSync } from "node:fs";
        import { join } from "node:path";

        const [, , piBin, ...packages] = process.argv;
        const fail = (message) => {
          console.error(message);
          process.exit(1);
        };

        const kinds = ["extensions", "skills", "prompts", "themes"];
        for (const root of packages) {
          const manifest = JSON.parse(readFileSync(join(root, "package.json"), "utf8")).pi;
          if (!manifest) {
            if (!kinds.some((kind) => existsSync(join(root, kind)))) fail(`''${root} has no pi resources`);
            continue;
          }
          for (const kind of kinds) {
            for (const entry of manifest[kind] ?? []) {
              if (entry.startsWith("!")) continue;
              if (!globSync(entry, { cwd: root }).length) fail(`''${root}: pi.''${kind} entry ''${entry} matches nothing`);
            }
          }
        }

        const started = Date.now();
        const elapsed = () => `''${((Date.now() - started) / 1000).toFixed(1)}s`;
        const seen = [];

        // CPU time tells a hang from slowness.
        const processes = () => {
          const all = readdirSync("/proc").filter((pid) => /^\d+$/.test(pid)).flatMap((pid) => {
            try {
              const stat = readFileSync(`/proc/''${pid}/stat`, "utf8");
              const fields = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
              const cmd = readFileSync(`/proc/''${pid}/cmdline`, "utf8").replaceAll("\0", " ").slice(0, 160);
              return [{ pid: Number(pid), state: fields[0], ppid: Number(fields[1]), cpu: (Number(fields[11]) + Number(fields[12])) / 100, cmd }];
            } catch {
              return [];
            }
          });
          const tree = new Set([pi.pid]);
          for (let grew = true; grew; ) {
            grew = false;
            for (const proc of all) {
              if (tree.has(proc.ppid) && !tree.has(proc.pid)) {
                tree.add(proc.pid);
                grew = true;
              }
            }
          }
          return all.filter((proc) => tree.has(proc.pid)).map((proc) => `  ''${proc.pid} ''${proc.state} cpu=''${proc.cpu}s ''${proc.cmd}`);
        };

        const pi = spawn(piBin, ["--mode", "rpc", "--no-session", "--offline"], {
          stdio: ["pipe", "pipe", "inherit"],
        });
        const stop = (message) => {
          pi.kill("SIGKILL");
          fail(message);
        };
        const timer = setTimeout(() => {
          console.error(`pi did not answer within 300s; stdout: ''${JSON.stringify(seen)}`);
          console.error(processes().join("\n"));
          stop("pi hung");
        }, 300000);
        pi.on("exit", (code) => stop(`pi exited with ''${code} before answering`));

        let buffer = "";
        pi.stdout.setEncoding("utf8");
        pi.stdout.on("data", (chunk) => {
          buffer += chunk;
          for (let end; (end = buffer.indexOf("\n")) >= 0; ) {
            const line = buffer.slice(0, end);
            buffer = buffer.slice(end + 1);
            let message;
            try {
              message = JSON.parse(line);
            } catch {
              continue;
            }
            seen.push(`''${elapsed()} ''${message.type}`);
            if (message.type === "extension_error") stop(`extension error: ''${line}`);
            if (message.type !== "response" || message.id !== "load") continue;
            clearTimeout(timer);
            console.log(`pi answered after ''${elapsed()}`);
            if (!message.success) stop(line);
            const sources = {};
            for (const command of message.data.commands) sources[command.source] = (sources[command.source] ?? 0) + 1;
            console.log("commands by source:", JSON.stringify(sources));
            if (!sources.extension) stop("no extension registered a command");
            // Late handler errors still count.
            setTimeout(() => {
              pi.removeAllListeners("exit");
              pi.on("exit", () => process.exit(0));
              pi.kill();
            }, 1000);
          }
        });
        pi.stdin.write(JSON.stringify({ type: "get_commands", id: "load" }) + "\n");
      '';

      # Background runs resolve these lazily.
      aliases = pkgs.writeText "pi-subagents-aliases.mjs" ''
        const [, , runnerAliases, piRoot] = process.argv;
        const { resolveHostPeerAliases } = await import(runnerAliases);
        const { missing } = resolveHostPeerAliases(piRoot);
        if (missing.length) {
          console.error(`pi lacks what pi-subagents needs: ''${missing.join(", ")}`);
          process.exit(1);
        }
      '';

      check =
        name: home:
        let
          pi = home.config.programs.pi;
          json = pkgs.formats.json { };
          agentFiles = lib.filter (file: file.enable && lib.hasPrefix ".pi/agent/" file.target) (
            lib.attrValues home.config.home.file
          );
          # Activation writes these, not home.file.
          written = {
            "settings.json" = pi.settings;
          }
          // lib.optionalAttrs (pi.claudeBridge.enable or false) {
            "claude-bridge.json" = pi.claudeBridge.settings;
          };
          agentDir = pkgs.linkFarm "pi-agent-${name}" (
            map (file: {
              name = lib.removePrefix ".pi/agent/" file.target;
              path = file.source;
            }) agentFiles
            ++ lib.mapAttrsToList (file: value: {
              name = file;
              path = json.generate file value;
            }) written
          );
          piRoot = "${pi.package}/lib/pi/node_modules/@earendil-works/pi-coding-agent";
          subagents = pi.subagents.enable or false;
        in
        pkgs.runCommand "pi-extensions-${name}" { nativeBuildInputs = [ pkgs.nodejs-slim ]; } ''
          export HOME=$TMPDIR/home PI_CODING_AGENT_DIR=$TMPDIR/agent
          export PI_OFFLINE=1 PI_SKIP_VERSION_CHECK=1 PI_TELEMETRY=0
          mkdir -p $HOME
          cp -rL ${agentDir} $PI_CODING_AGENT_DIR
          chmod -R u+w $PI_CODING_AGENT_DIR

          found=0
          for package in ${lib.escapeShellArgs pi.settings.packages}; do
            runner=$package/src/runs/background/runner-aliases.js
            if [ -e "$runner" ]; then
              node ${aliases} "$runner" ${piRoot}
              found=1
            fi
          done
          if ${lib.boolToString subagents} && [ "$found" = 0 ]; then
            echo "pi-subagents moved runner-aliases.js; update this check"
            exit 1
          fi

          node ${driver} ${lib.getExe pi.package} ${lib.escapeShellArgs pi.settings.packages}
          touch $out
        '';
    in
    {
      checks = lib.mapAttrs' (
        name: home: lib.nameValuePair "pi-extensions-${name}" (check name home)
      ) homes;
    };
}
