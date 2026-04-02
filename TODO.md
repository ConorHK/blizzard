generate a registration token from GitHub (Settings →
  Actions → Runners → New self-hosted runner, or via the API),
   then:

  # From the dev shell
  agenix -e modules/nixos/server/github-runner/secrets/github-
  runner-token.age
  # Paste the token and save
  agenix rekey

  The github-runner-cachix secret reuses the existing
  encrypted source from the cachix module, so no separate file
   is needed — it'll just be rekeyed for leprechaun's host
  key.

  How it works:
  - services.github-runners.blizzard runs as user
  github-runner-blizzard
  - cachix watch-store runs as the same user, watching the Nix
   store via inotify
  - Any path built during a CI run is automatically pushed to
  conorhk.cachix.org
  - No root involvement, no post-build-hook

  You'll also need to update the workflow's runs-on values to
  include [self-hosted, nix, x86_64-linux] labels for the jobs
   you want to run on leprechaun.
