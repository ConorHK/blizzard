{ config, ... }:
{
  flake.modules.homeManager.core =
    { config, pkgs, ... }:
    {
      age.secrets.ntfy-topic.rekeyFile = ./ntfy-topic.age;
      home.packages =
        let
          notify-script = pkgs.writeScriptBin "notify" ''
            #!${pkgs.python3.withPackages (ps: with ps; [ requests ])}/bin/python3

            import sys
            import time
            from datetime import timedelta
            from os import getenv
            from subprocess import run as subprocess_run

            from requests import post

            # Override priorities by inline setting env variables e.g. > SUCCESS_PRIORITY=5 notify ...
            SUCCESS_PRIORITY = int(getenv("SUCCESS_PRIORITY", 3))
            FAILURE_PRIORITY = int(getenv("FAILURE_PRIORITY", 4))

            # Hide sensitive commands by inline setting env variable
            ALIAS = getenv("ALIAS", None)

            # Read NTFY_TOPIC from agenix file
            NTFY_TOPIC_FILE = "${config.age.secrets.ntfy-topic.path}"
            with open(NTFY_TOPIC_FILE, "r") as f:
                NTFY_TOPIC = f.read().strip()


            def _send_notification(command, error, execution_time) -> None:
                data = {
                    "topic": NTFY_TOPIC,
                    "tags": ["tada"],
                    "message": f"{command} :: completed with return code {error} in {execution_time}",
                    "title": "Command success",
                    "priority": SUCCESS_PRIORITY,
                }
                if error:
                    data["title"] = "Command failure"
                    data["priority"] = FAILURE_PRIORITY
                    data["tags"] = ["warning"]

                post("https://ntfy.sh", json=data)


            def main() -> None:
                if not all(1 <= priority <= 5 for priority in [SUCCESS_PRIORITY, FAILURE_PRIORITY]):
                    msg = "Priority ranges between 1 (minimum) and 5 (maximum)"
                    raise ValueError(msg)

                command = sys.argv[1:]
                start_time = time.monotonic()
                process = subprocess_run(command, check=False)
                end_time = time.monotonic()
                command_string = ALIAS if ALIAS else " ".join(command)
                _send_notification(command_string, process.returncode, timedelta(seconds=end_time - start_time))


            if __name__ == "__main__":
                main()
          '';
        in
        [ notify-script ];

    };
}
