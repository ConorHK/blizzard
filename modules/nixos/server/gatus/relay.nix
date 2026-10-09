_: {
  flake.modules.nixos.gatus-relay =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.gatusRelay;

      relay = pkgs.writers.writePython3Bin "gatus-relay" { } ''
        import http.server
        import json
        import os
        import subprocess
        import threading

        PORT = int(os.environ["RELAY_PORT"])
        WINDOW = int(os.environ["RELAY_WINDOW"])
        STATE = os.path.join(os.environ["STATE_DIRECTORY"], "pending.json")
        VERBS = {"TRIGGERED": "down", "RESOLVED": "recovered"}

        lock = threading.Lock()
        timer = None


        def load():
            try:
                with open(STATE) as f:
                    return json.load(f)
            except FileNotFoundError:
                return {}


        pending = load()


        def save():
            tmp = STATE + ".tmp"
            with open(tmp, "w") as f:
                json.dump(pending, f)
            os.replace(tmp, STATE)


        def arm():
            global timer
            if timer is None:
                timer = threading.Timer(WINDOW, flush)
                timer.start()


        def send(names, batch, verb):
            if len(names) == 1:
                title = f"{names[0]} {verb}"
                message = batch[names[0]]["errors"] or title
            else:
                title = f"{len(names)} checks {verb}"
                message = ", ".join(names)
            priority, tag = (
                ("4", "warning") if verb == "down"
                else ("3", "white_check_mark")
            )
            subprocess.run(["alert-send", title, message, priority, tag])


        def flush():
            global timer
            with lock:
                timer = None
                batch = dict(pending)
            for state, verb in VERBS.items():
                names = sorted(n for n, e in batch.items() if e["state"] == state)
                if names:
                    send(names, batch, verb)
            # Keep events that changed while sending.
            with lock:
                for name, event in batch.items():
                    if pending.get(name) == event:
                        del pending[name]
                save()
                if pending:
                    arm()


        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                state, name, errors = (
                    body.decode(errors="replace").split("\n", 2) + ["", ""]
                )[:3]
                if state not in VERBS or not name:
                    self.send_response(400)
                    self.end_headers()
                    return
                with lock:
                    pending[name] = {"state": state, "errors": errors.strip()}
                    save()
                    arm()
                self.send_response(204)
                self.end_headers()

            def log_message(self, *args):
                pass


        with lock:
            if pending:
                arm()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
        server.serve_forever()
      '';
    in
    {
      options.blizzard.gatusRelay = {
        topicFile = lib.mkOption {
          type = lib.types.path;
          description = "File sourced for NTFY_TOPIC.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8099;
        };

        window = lib.mkOption {
          type = lib.types.ints.positive;
          default = 90;
          description = "Seconds to collect alerts before one notification.";
        };
      };

      config = {
        services.gatus.settings.alerting.custom = {
          url = "http://127.0.0.1:${toString cfg.port}/";
          method = "POST";
          body = "[ALERT_TRIGGERED_OR_RESOLVED]\n[ENDPOINT_NAME]\n[RESULT_ERRORS]";
          default-alert = {
            enabled = true;
            failure-threshold = 2;
            success-threshold = 1;
            send-on-resolved = true;
          };
        };

        systemd.services = {
          gatus = {
            wants = [ "gatus-relay.service" ];
            after = [ "gatus-relay.service" ];
          };

          gatus-relay = {
            description = "Batch gatus alerts into ntfy";
            wantedBy = [ "multi-user.target" ];
            path = [ config.blizzard.alerts.send ];
            environment = {
              RELAY_PORT = toString cfg.port;
              RELAY_WINDOW = toString cfg.window;
              ALERT_TOPIC_FILE = cfg.topicFile;
            };
            unitConfig.OnFailure = "alert-failure@gatus-relay.service";
            serviceConfig = {
              ExecStart = lib.getExe relay;
              Restart = "on-failure";
              StateDirectory = "gatus-relay";
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
            };
          };
        };
      };
    };
}
