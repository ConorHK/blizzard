# cloudflare-share — temporary, opt-in public sharing

A **reusable "sharing switch"** for exposing individual services to guests over the
public internet for a bounded time window, then closing automatically.

Goal: share a service with people who only have a browser (no Tailscale install),
gated behind a login, **without** exposing leprechaun's WAN IP or opening any
inbound hole in the home network. Achieved with an **outbound** Cloudflare Tunnel
plus Cloudflare Access (email one-time-PIN) at the edge.

Status: **scaffolded, dormant, not yet wired to a real service.** The Cloudflare-side
setup (account, DNS delegation, tunnel, Access policy) has not been done — see
"Manual setup (do once)" below. Nothing here exposes anything until both the manual
setup is complete *and* `share-open` is run.

## Why this design (decisions already made)

- **Guests use a plain browser URL, gated by a login.** → Cloudflare Tunnel + Access
  with email OTP. No client install for guests; Access provides auth for apps that
  have none of their own.
- **Do not expose the home network.** → `cloudflared` makes an *outbound* connection
  to Cloudflare. No router port-forward, no inbound firewall change, WAN IP hidden.
  (Chosen over a router DMZ/port-forward, which has fewer third-party deps but
  exposes the home IP and opens inbound to the LAN.)
- **Tailscale Funnel was rejected** because it has no built-in auth — meeting the
  "behind a login" requirement would mean running oauth2-proxy/Authelia ourselves.
  Cloudflare Access is fewer moving parts.
- **Opt-in, time-boxed, auto-closing.** The connector is defined in Nix but
  `autoStart = false` — dormant until explicitly started. Opening a share schedules
  its own stop via a transient `systemd-run --on-active` timer.
- **CLI-only trigger, explicit duration required.** `share-open <service> <duration>`
  errors if no duration is given — every share is a conscious choice. (A phone
  trigger, e.g. Home Assistant / ntfy action, can be layered on later by calling the
  same command; the mechanism is built to allow it without rework.)
- **Reboot fails closed.** Because the connector is not `wantedBy` boot, a reboot
  mid-window leaves the share *closed*. Correct bias for a public exposure.

## Blast-radius hardening (why it's not the default host daemon)

Most `cloudflared` guides run it as a host daemon whose ingress can reach anything
the host can — every `127.0.0.1:<port>` service and the whole LAN. Two vectors,
two mitigations:

1. **Ingress re-pointed (Cloudflare account/token compromise).**
   → Use a **locally-managed tunnel**: `credentials.json` + a fixed `ingress:` block
   in a local `config.yml` on leprechaun. Targets are pinned in Nix and cannot be
   changed from the Cloudflare side.

2. **Connector process popped (RCE).**
   → Run `cloudflared` as a **quadlet container joined to only the shared service's
   podman network**, with ingress pointing at the container's DNS name
   (`http://<service>:<port>`), not a host loopback port. It then has **no route** to
   other services' loopback ports — they live on separate podman networks and are
   invisible. One shared network per service ⇒ a compromised connector for one share
   can't pivot to another.

**Known residual risk:** rootless podman (pasta/slirp) still permits *outbound*
reachability from the container to the LAN. Namespace isolation removes the
"reach other loopback services / re-point ingress" vectors but not outbound-initiated
connections. If a shared service is genuinely untrusted, add egress filtering on the
connector container (allow out only to Cloudflare's edge). Not done by default.

## Architecture

```
share-open budget 4h
   │  systemctl --user start  cloudflared-share@budget
   │  systemd-run --user --on-active=4h  → stop it, timer self-destructs
   ▼
cloudflared (container, joined ONLY to budget's podman network)
   │  outbound 443
   ▼
Cloudflare edge
   ├─ Access application: email-OTP policy, allowlisted guest emails
   └─ public hostname budget.share.goosebox.org → ingress → http://actual-budget:5006
```

## Manual setup (do once, cannot live in Nix)

1. Create a free Cloudflare account.
2. Get a zone for the share hostnames onto it. **Recommended: delegate a subdomain**
   `share.goosebox.org` by adding NS records at Namecheap → Cloudflare. This leaves
   the existing `goosebox.org` + Let's Encrypt (namecheap DNS-01) setup completely
   untouched; only `*.share.goosebox.org` lives on Cloudflare. (Alternative: a
   separate throwaway domain.)
3. Create a **locally-managed** tunnel:
   ```
   cloudflared tunnel login
   cloudflared tunnel create leprechaun-share
   ```
   This yields a `<TUNNEL_ID>.json` credentials file and a tunnel UUID.
4. Encrypt the credentials file into this module's secrets with agenix-rekey
   (see "Wiring a service" step for the exact secret name), then commit the `.age`.
5. For **each** hostname you share, create a Cloudflare **Access application**:
   - Application domain: e.g. `budget.share.goosebox.org`
   - Policy: action *Allow*, include *Emails* → the specific guest addresses
   - Identity/method: **One-time PIN** (email OTP).
6. Add the tunnel's public hostname routes (or let the local `config.yml` ingress
   plus a `cloudflared tunnel route dns` call create the CNAMEs).

## Wiring a service (per share, in Nix)

The module is parameterized over an attrset of shares. To add one, give it:
- `network`  — the service's existing podman network (e.g. `"actual-budget.network"`)
- `target`   — container DNS name + port (e.g. `"http://actual-budget:5006"`)
- `hostname` — public name on the Cloudflare zone (e.g. `"budget.share.goosebox.org"`)

Adding a share is a one-line entry in `cloudflare-share.nix`'s `shares` attrset.
No other change is needed. Rebuild leprechaun to make the (still dormant) unit exist.

Prefer that the shared service's container **not** publish a host port at all
(`publishPorts` can be dropped for it) — the connector reaches it purely over the
shared podman network, so nothing on the host loopback needs to see it.

## Everyday use (CLI on leprechaun)

```
share-open <service> <duration>   # e.g. share-open budget 4h  — duration is REQUIRED
share-status                      # what's open and how long remains
share-close <service>             # close early; cancels the pending auto-close timer
```

`<duration>` is any systemd time span (`90m`, `4h`, `1d`). Omitting it is an error.

## Teardown / kill switch

- Close one share now: `share-close <service>`.
- Disable the whole capability: remove `cloudflare-share` from
  `modules/hosts/leprechaun/imports.nix` and `rebuild leprechaun`. Because exposure
  is outbound-only, there is no router/firewall state to also unwind.
- Revoke at the edge: delete the tunnel or the Access application in Cloudflare.

## TODO before first real use

- [ ] Do the manual Cloudflare setup above (account, `share.goosebox.org` delegation,
      tunnel, per-hostname Access email-OTP policies).
- [ ] Encrypt the tunnel credentials into `secrets/` and set the correct secret name.
- [ ] Add the first real service to the `shares` attrset (network/target/hostname).
- [ ] Register the module in `modules/hosts/leprechaun/imports.nix`.
- [ ] `rebuild leprechaun`, then dry-run `share-open <service> 15m` and confirm the
      guest URL prompts for an email OTP and reaches only that one service.
- [ ] Decide whether the shared service's container should stop publishing a host port.
- [ ] (Optional) Add egress filtering on the connector container if the shared
      service is untrusted.
