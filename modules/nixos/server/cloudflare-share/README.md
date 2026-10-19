# cloudflare-share

Opens a leprechaun service to guests on the public internet for a set time,
then closes it on its own.

Guests need only a browser and an email address. They do not install
Tailscale. leprechaun's WAN IP stays hidden and the home network opens no
inbound port. An outbound Cloudflare Tunnel carries the traffic, and
Cloudflare Access gates it with an email one-time PIN.

The module is scaffolded and dormant. No service is wired yet, and the
Cloudflare side (account, DNS delegation, tunnels, Access policies) does not
exist. Nothing is exposed until that setup is done and someone runs
`share-open`.

## Design

- Guests get a plain URL behind a login. Cloudflare Access supplies the
  login, so apps with no auth of their own are still gated.
- `cloudflared` connects out to Cloudflare. No router port-forward, no
  firewall change. A router port-forward would need fewer third parties but
  would expose the home IP and open the LAN to inbound traffic.
- Tailscale Funnel has no built-in auth. Meeting the login requirement would
  mean running oauth2-proxy or Authelia here, which is more to maintain than
  Access.
- Each connector container has `autoStart = false`. It exists after a
  rebuild but runs only when `share-open` starts it.
- `share-open` requires a duration and schedules its own stop with a
  transient `systemd-run --on-active` timer. A later trigger, such as a Home
  Assistant or ntfy action, can call the same command.
- No connector is wanted by boot, so a reboot mid-window leaves the share
  closed.

## Limiting the blast radius

Most guides run `cloudflared` as a host daemon, which can reach every
`127.0.0.1` service and the whole LAN. This module closes two paths:

1. A compromised Cloudflare account or token cannot re-point ingress. Each
   tunnel is locally managed: a credentials file plus a fixed `ingress`
   block in a local `config.yml`, both pinned in Nix. Hostnames other than
   the share's return 404 at the connector.
2. A compromised connector process cannot reach other services. Each share
   runs `cloudflared` as a rootless quadlet container joined only to that
   service's podman network, and ingress points at the container's DNS name
   (`http://<service>:<port>`), not a host port. Other services live on
   other networks. Each share gets its own tunnel and connector, so one
   compromised share cannot reach another.

Rootless podman still lets the container open outbound connections to the
LAN. If a shared service is untrusted, add egress filtering on its
connector so it can reach only Cloudflare's edge. The module does not do
this by default.

## Architecture

```
share-open budget 4h
   | systemctl --user start cloudflared-share-budget
   | systemd-run --user --on-active=4h (stops it, then expires)
   v
cloudflared container, on budget's podman network only
   | outbound 443
   v
Cloudflare edge
   |- Access application: email OTP, allowlisted guest emails
   '- budget.share.goosebox.org -> ingress -> http://actual-budget:5006
```

## One-time setup outside Nix

1. Create a free Cloudflare account.
2. Delegate `share.goosebox.org` to Cloudflare with NS records in deSEC.
   The rest of `goosebox.org` and its ACME certificates stay on deSEC. A
   separate throwaway domain also works.
3. For each share, create a locally managed tunnel:
   ```
   cloudflared tunnel login
   cloudflared tunnel create leprechaun-share-<name>
   ```
   This prints the tunnel UUID and writes a `<UUID>.json` credentials file.
4. Encrypt the credentials file to `secrets/<name>.json.age` with
   agenix-rekey, `git add` it, then rekey and commit.
5. For each share hostname, create a Cloudflare Access application:
   - Domain, such as `budget.share.goosebox.org`.
   - Policy: allow, including only the guest email addresses.
   - Login method: one-time PIN.
6. Point the hostname at the tunnel with
   `cloudflared tunnel route dns <tunnel> <hostname>`.

## Wiring a share

Add an entry to `shares` in `cloudflare-share.nix`:

| Field | Value | Example |
|---|---|---|
| `network` | The service's podman network | `"actual-budget.network"` |
| `target` | Container DNS name and port | `"http://actual-budget:5006"` |
| `hostname` | Public name on the Cloudflare zone | `"budget.share.goosebox.org"` |
| `tunnel` | Tunnel UUID from setup step 3 | |

The module then expects the agenix secret `cloudflare-share-<name>`, backed
by `secrets/<name>.json.age`. Rebuild leprechaun to create the dormant unit.

The connector reaches the service over the podman network, so the service
does not need to publish a host port. Consider dropping its `publishPorts`.

## Use

On leprechaun:

```
share-open <service> <duration>   # duration is required, such as 4h
share-status                      # open shares and time left
share-close <service>             # close now, cancel the timer
```

`<duration>` takes any systemd time span: `90m`, `4h`, `1d`.

## Shut it off

- Close one share: `share-close <service>`.
- Remove the feature: drop `cloudflare-share` from
  `modules/hosts/leprechaun/imports.nix` and run `rebuild leprechaun`.
  Traffic is outbound only, so no router or firewall state needs undoing.
- Revoke at the edge: delete the tunnel or the Access application in
  Cloudflare.

## Before first use

- [ ] Do the one-time setup above.
- [ ] Add the first service to `shares`.
- [ ] Add `cloudflare-share` to `modules/hosts/leprechaun/imports.nix`.
- [ ] Run `rebuild leprechaun`, then `share-open <service> 15m`. Confirm the
      guest URL asks for an email PIN and reaches only that service.
- [ ] Decide whether the service should stop publishing a host port.
- [ ] Add egress filtering on the connector if the service is untrusted.
