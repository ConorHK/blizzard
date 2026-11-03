# Revolut import

Revolut has no personal API, so statements reach Actual from the phone:

```
Revolut app: export CSV -> Open with "Send to Actual"
  -> POST http://10.100.0.1:8097/import  (over WireGuard, bearer token)
  -> revolut-import on leprechaun -> @actual-app/api importTransactions
  -> Actual at 127.0.0.1:5006
```

Card statements only cover closed months, so card spends also arrive live:

```
Revolut notification "You spent EUR 25 / Available credit ..."
  -> RevolutListener (notification access) queues it on the phone
  -> POST /notify -> addTransactions, uncleared, no imported_id
  -> month-end CSV import fuzzy-matches and settles it
```

## Pieces

- The Android app is in [`modules/packages/revolut-share/`](../modules/packages/revolut-share/),
  built by [`revolut-share.nix`](../modules/packages/revolut-share.nix) with
  aapt2, javac and d8, no Gradle. It has a settings screen for the URL and
  token, and a translucent activity that takes the file from "Open with" or
  "Share", uploads it, and shows the result as a toast.
- The service is [`modules/nixos/server/revolut-import/`](../modules/nixos/server/revolut-import/).
  [`revolut.js`](../modules/nixos/server/revolut-import/src/revolut.js) parses
  the CSV; [`server.js`](../modules/nixos/server/revolut-import/src/server.js)
  downloads the budget, imports, syncs and closes it on every request.
- It listens on the wg0 address only, so only WireGuard peers reach it. The
  token stops other processes on leprechaun, such as containers, from
  writing to the budget.

## Parsing rules

- A row imports once it has a Completed Date, and its State, if the export
  has that column, is `COMPLETED`.
- Amount is `Amount - Fee`, since Revolut reports fees as a positive charge.
- The date is the Started Date, when the purchase happened.
- `imported_id` hashes product, start time, amount and description, so
  overlapping exports never add a transaction twice.
- Rows route to Actual accounts by the Product column through `accounts`.
  Credit card exports have no Product column and go to `defaultAccount`. An
  unmapped product fails the whole import with its name in the error.

## Notification rules

- Only `com.revolut.revolut` notifications containing "You spent" are sent.
  Text mentioning available credit goes to `defaultAccount` (the card); any
  other spend goes to `spendAccount`.
- Entries skip `imported_id` on purpose. Actual only fuzzy-matches existing
  transactions without one, by equal amount within 7 days, so the CSV row
  settles the entry instead of adding a second one.
- They go in with `addTransactions`, which never merges, so two equal
  coffees stay two entries. The server keeps the last 1000 notification ids
  in `notified.json` to drop reposts.
- The phone queues unsent items and retries on the next notification and
  whenever the settings screen opens.

## Install the app

Plug the phone in with USB debugging on, then:

```bash
nix run .#revolut-share   # USB device; set ANDROID_SERIAL to pick another
```

It signs the APK with `~/.android/debug.keystore`, so later installs update
in place. Open "Send to Actual" once, paste the token, then tap
"Notification access" and allow it.

## Upgrades

`@actual-app/api` in `src/package.json` must match the actual-server image
version. Renovate bumps both in one `actual-budget` PR and refreshes the
lockfile with it; its other npm deps share a `revolut-import` PR.
