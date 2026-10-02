{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Keyring loads a per-arch native binding.
      keyringNative =
        {
          x86_64-linux = {
            "@napi-rs/keyring-linux-x64-gnu" = {
              version = "2.1.0";
              hash = "sha512-7ZA0ssxfpuGXV8S5Ct1ZJoEL3sKg/8u7mIL4SK9/PwKBhxIq7K+FVcjnggNsuFnEhHTX+HYl9hHDrlX0odZnHg==";
            };
          };
          aarch64-linux = {
            "@napi-rs/keyring-linux-arm64-gnu" = {
              version = "2.1.0";
              hash = "sha512-+PMONFQ+2GkBXG7vRG2spgR73bNCMeVpNopHoSmhj2E+5Gu6zJooRBjoaIZKj6hCyrOU8pXAhoZ22EEFQ/4YeQ==";
            };
          };
        }
        .${pkgs.stdenv.hostPlatform.system} or { };
      # recheck natives skipped: pure JS fallback.
      deps = {
        "@modelcontextprotocol/client" = {
          version = "2.0.0";
          hash = "sha512-8f1OghQ2rjzIOfqgUCP+8GiUWqRs89njoWLNqAe8kWmDePv3s1fZXseej+QXemssEuuOvLLmLO/kqM3IQHtISw==";
        };
        "@modelcontextprotocol/core" = {
          version = "2.0.0";
          hash = "sha512-pJCEwGG7Lfr/+PQp9ZTwKXNeO5wzbfKL7H3MYpCorM4oFBoQrdjnBgEoqG+RjhsvS1FKrDbKux+M1HhlnGWqcA==";
        };
        "@modelcontextprotocol/ext-tasks" = {
          version = "0.1.0";
          hash = "sha512-N6kQdDoR8bQcXFvoB0qsPh2k5/hr+aQDKngiJH8P2u3L68bdX0yMuPRMAZ6JHBGTA51rRFc3ajhiosEaeW9U1A==";
        };
        "@napi-rs/keyring" = {
          version = "2.1.0";
          hash = "sha512-km9J3fomkGSLpImpelq0cMvLBrJ5eVlTzuWdG3Iy0laP6gU90MmHYjqhUhG32aYq0/0++r2TLuAA9xlnh4XU1g==";
        };
        "@pkgr/core" = {
          version = "0.2.10";
          hash = "sha512-x6fFWCeak8aCGfqZfe6CXYt5xVjxe9Os1cIPmVRcToInKLjhJkRVXvJ/L3/1KxFkjDQdbZV/YsuLKqa8t/xKpA==";
        };
        "@typesafe-ai/sdk" = {
          version = "0.6.0";
          hash = "sha512-IddX+Q0XM+VagOUZFeP7wZjaO4SHMdvnh2zEBdrZZnXedWI3BNK1lKhMx3ayrkFWvVLbVcUHJy6AVZlY+e6Jaw==";
        };
        ajv = {
          version = "8.20.0";
          hash = "sha512-Thbli+OlOj+iMPYFBVBfJ3OmCAnaSyNn4M1vz9T6Gka5Jt9ba/HIR56joy65tY6kx/FCF5VXNB819Y7/GUrBGA==";
        };
        ajv-formats = {
          version = "3.0.1";
          hash = "sha512-8iUql50EUR+uUcdRQ3HDqa6EVyo3docL8g5WJ3FNcWmu62IbkGUue/pEyLBW8VGKKucTPgqeks4fIU1DA4yowQ==";
        };
        bundle-name = {
          version = "4.1.1";
          hash = "sha512-DdH81/zPLVS11EUgWq3tEu/xn+EzljlMYooDNdzWEnFha3R3NBMpMV1UqYIpjYHV/SgpFKMIX1Oh7o06SjM/oA==";
        };
        cross-spawn = {
          version = "7.0.6";
          hash = "sha512-uV2QOWP2nWzsy2aMp8aRibhi9dlzF5Hgh5SHaB9OiTGEyDTiJJyx0uy51QXdyWbtAHNua4XJzUKca3OzKUd3vA==";
        };
        default-browser = {
          version = "5.5.1";
          hash = "sha512-m1pAzaJgZ/gssEqlOhJkPJp8Xly7QyW6xcrkUa2KKcDeDSEMP7X8xipU3snUcfisTQx0w1AGae+9UtJSfVnXGw==";
        };
        default-browser-id = {
          version = "5.0.1";
          hash = "sha512-x1VCxdX4t+8wVfd1so/9w+vQ4vx7lKd2Qp5tDRutErwmR85OgmfX7RlLRMWafRMY7hbEiXIbudNrjOAPa/hL8Q==";
        };
        define-lazy-prop = {
          version = "3.0.0";
          hash = "sha512-N+MeXYoqr3pOgn8xfyRPREN7gHakLYjhsHhWGT3fWAiL4IkAt0iDw14QiiEm2bE30c5XX5q0FtAA3CK5f9/BUg==";
        };
        eventsource = {
          version = "3.0.7";
          hash = "sha512-CRT1WTyuQoD771GW56XEZFQ/ZoSfWid1alKGDYMmkt2yl8UXrVR4pspqWNEcqKvVIzg6PAltWjxcSSPrboA4iA==";
        };
        eventsource-parser = {
          version = "3.1.1";
          hash = "sha512-EKN1vKAMcZ8MlYMpaNuxN6R9yakzH6uajHcHVTqWJzvu5pWw9DyhbP35HH8MVBQ+dZjAfDxk+A8NiR9KWaXiyQ==";
        };
        fast-deep-equal = {
          version = "3.1.3";
          hash = "sha512-f3qQ9oQy9j2AhBe/H9VC91wLmKBCCU/gDOnKNAYG5hswO7BLKj09Hc5HYNz9cGI++xlpDCIgDaitVs03ATR84Q==";
        };
        fast-uri = {
          version = "3.1.8";
          hash = "sha512-GZMtZUTNRpOVIECoXwLNZS5xUGE+mVNbTB8h/7Rwh2TFWcBQiPzTgyZi05BF9UMZKkLJv8XBRJTlU7zg8+ZfMg==";
        };
        is-docker = {
          version = "3.0.0";
          hash = "sha512-eljcgEDlEns/7AXFosB5K/2nCM4P7FQPkGc/DWLy5rmFEWvZayGrik1d9/QIY5nJ4f9YsVvBkA6kJpHn9rISdQ==";
        };
        is-inside-container = {
          version = "1.0.0";
          hash = "sha512-KIYLCCJghfHZxqjYBE7rEy0OBuTd5xCHS7tHVgvCLkx7StIoaxwNW3hCALgEUjFfeRk+MG/Qxmp/vtETEF3tRA==";
        };
        is-wsl = {
          version = "3.1.1";
          hash = "sha512-e6rvdUCiQCAuumZslxRJWR/Doq4VpPR82kqclvcS0efgt430SlGIk05vdCN58+VrzgtIcfNODjozVielycD4Sw==";
        };
        isexe = {
          version = "2.0.0";
          hash = "sha512-RHxMLp9lnKHGHRng9QFhRCMbYAcVpn69smSGcq3f36xjgVVWThj4qqLbTLlq7Ssj8B+fIQ1EuCEGI2lKsyQeIw==";
        };
        jose = {
          version = "6.2.12";
          hash = "sha512-9NiFmJEex0sy2Dk58j2UGBSHgUs2ypF9eZSu4L6vjOX3Dp96Sw1F3uL+H+D1sx02jZZdzUT0HgvCy59CuvXcWw==";
        };
        json-schema-traverse = {
          version = "1.0.0";
          hash = "sha512-NM8/P9n3XjXhIZn1lLhkFaACTOURQXjWhV4BA/RnOv8xvgqtqpAX9IO4mRQxSx1Rlo4tqzeqb0sOlruaOy3dug==";
        };
        open = {
          version = "10.2.0";
          hash = "sha512-YgBpdJHPyQ2UE5x+hlSXcnejzAvD0b22U2OuAP+8OnlJT+PjWPxtgmGqKKc+RgTM63U9gN0YzrYc71R2WT/hTA==";
        };
        path-key = {
          version = "3.1.1";
          hash = "sha512-ojmeN0qd+y0jszEtoY48r0Peq5dwMEkIlCOu6Q5f41lfkswXuKtYrhgoTpLnyIcHm24Uhqx+5Tqm2InSwLhE6Q==";
        };
        pkce-challenge = {
          version = "5.0.1";
          hash = "sha512-wQ0b/W4Fr01qtpHlqSqspcj3EhBvimsdh0KlHhH8HRZnMsEa0ea2fTULOXOS9ccQr3om+GcGRk4e+isrZWV8qQ==";
        };
        quickjs-wasi = {
          version = "3.6.2";
          hash = "sha512-FCqGtGOrMgzUiIrMNMA2YnsOxCNwo31dzqXvclXUC6xeT35NJLKXQJsvbeCTjvoFAwZgEAPg8U6+KAPDGXn8Mg==";
        };
        recheck = {
          version = "4.6.0-beta.3";
          hash = "sha512-vFGnR2AF6o8O5/gyLoIx5Kcnqdf/e3RLeMbZYgTJAiTIkKFPEFAWKxHiGWOhZDg5ibt46oqN7h+yJE6Gx2HqYw==";
        };
        require-from-string = {
          version = "2.0.2";
          hash = "sha512-Xf0nWe6RseziFMu+Ap9biiUbmplq6S9/p+7w7YXP/JBHhrUDDUhwa+vANyubuqfZWTveU//DYVGsDG7RKL/vEw==";
        };
        run-applescript = {
          version = "7.1.0";
          hash = "sha512-DPe5pVFaAsinSaV6QjQ6gdiedWDcRCbUuiQfQa2wmWV7+xC9bGulGI8+TdRmoFkAPaBXk8CrAbnlY2ISniJ47Q==";
        };
        shebang-command = {
          version = "2.0.0";
          hash = "sha512-kHxr2zZpYtdmrN1qDjrrX/Z1rR1kG8Dx+gkpK1G4eXmvXswmcE1hTWBWYUzlraYw1/yZp6YuDY77YtvbN0dmDA==";
        };
        shebang-regex = {
          version = "3.0.0";
          hash = "sha512-7++dFhtcx3353uBaq8DDR4NuxBetBzC7ZQOhmTQInHEd6bSrXdiEyzCvG07Z44UYdLShWUyXt5M/yhz8ekcb1A==";
        };
        smol-toml = {
          version = "1.9.0";
          hash = "sha512-hpd+HLON7HdZXqYchMM/+LaTTbdK0AU3NngIJ4KVyWbY9bfQqdL9cD+4yf6dUoU2Ap4VsU0JkQi6FxAI1B2mXQ==";
        };
        strip-json-comments = {
          version = "5.0.3";
          hash = "sha512-1tB5mhVo7U+ETBKNf92xT4hrQa3pm0MZ0PQvuDnWgAAGHDsfp4lPSpiS6psrSiet87wyGPh9ft6wmhOMQ0hDiw==";
        };
        synckit = {
          version = "0.11.11";
          hash = "sha512-MeQTA1r0litLUf0Rp/iisCaL8761lKAZHaimlbGK4j0HysC4PLfqygQj9srcs0m2RdtDYnF8UuYyKpbjHYp7Jw==";
        };
        undici = {
          version = "6.29.0";
          hash = "sha512-R+RODBqp6i2pPflGdq+xIOUkl+RNfGgHwoinecKu/JCuf2uO06cOKoDbI2P7Dn6KcswdKwrczbU6IYJ6K8X+wg==";
        };
        which = {
          version = "2.0.2";
          hash = "sha512-BLI3Tl1TW3Pvl70l3yq3Y64i+awpwXqsGBYWkkqMtnbXgrMD+yj7rhW0kuEDxzJaYXGjEW5ogapKNMEKNMjibA==";
        };
        wsl-utils = {
          version = "0.1.0";
          hash = "sha512-h3Fbisa2nKGPxCpm89Hk33lBLsnaGBvctQopaBSOW/uIs6FTe1ATyAnKFJrzVs9vpGdsTe73WF3V4lIsk4Gacw==";
        };
        zod = {
          version = "4.6.5";
          hash = "sha512-v5l/aFXZQeai4awLbOpSoHecE9UiMrnfx75tEXLjNonXVARxQ5mOeipTjROUchszUNCqnE+hqAMujRsRHsut2Q==";
        };
      }
      // keyringNative;
      depSrcs = lib.mapAttrs (
        name:
        { version, hash }:
        pkgs.fetchurl {
          url = "https://registry.npmjs.org/${name}/-/${baseNameOf name}-${version}.tgz";
          inherit hash;
        }
      ) deps;
      pi-mcp-adapter = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-mcp-adapter";
        version = "5.0.0";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-mcp-adapter/-/pi-mcp-adapter-${version}.tgz";
          hash = "sha512-/3vWQLSXwud+VX1vV/dFfKpp6I40guCeqiaP/XMdXIyon+frIm+sPXGArLlmvY5PIwL2ChJ3AhELIusroGA8Ng==";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          tar xzf $src -C $out --strip-components=1
        ''
        + lib.concatStrings (
          lib.mapAttrsToList (name: tgz: ''
            mkdir -p $out/node_modules/${name}
            tar xzf ${tgz} -C $out/node_modules/${name} --strip-components=1
          '') depSrcs
        )
        + ''
          runHook postInstall
        '';
      };
    in
    {
      options.programs.pi.mcpAdapter.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-mcp-adapter package.";
      };

      config = lib.mkIf config.programs.pi.mcpAdapter.enable {
        programs.pi.settings = {
          # Package entry: loads the manifest extension.
          packages = [ "${pi-mcp-adapter}" ];
          # The adapter replaces built-in MCP.
          extensions = [ "-builtin:mcp" ];
        };
      };
    };
}
