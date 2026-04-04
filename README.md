# blizzard

| Hostname     | Description                 |
| ----------   | ----------------------------|
| **abhartach**| Workstation PC              |
| **bananach** | Monitor VPS                 |
| **banshee**  | Audio server Pi             |
| **dullahan** | Laptop                      |
| **puca**     | HomeAssistant Fuji          |
| **leprechaun** | Home server               |

## leprechaun services

| Module | Services | Ports |
|--------|----------|-------|
| `arr` | sonarr, radarr, bazarr, prowlarr, jellyseerr, qbittorrent, cross-seed, recyclarr, unpackerr, qbit-manage, jellystat | 8989, 7878, 6767, 9696, 5055, 8080, 2468, 3000 |
| `actual-budget` | actual-server | 5006 |
| `audiobookshelf` | audiobookshelf | 13378 |
| `backrest` | backrest | 9898 |
| `boinc` | boinc (host network) | — |
| `caldav` | radicale | 5232 |
| `calibre` | calibre-web, book-downloader, cf-bypass, openbooks | 8183, 8085, 8086 |
| `dawarich` | redis, postgis, app, sidekiq | 3001 |
| `freshrss` | freshrss | 8002 |
| `glance` | glance | 8090 |
| `immich` | redis, postgres, machine-learning, server | 2283 |
| `jellyfin` | jellyfin (host network) | — |
| `mealie` | mealie | 9925 |
| `music` | gonic, octo-fiesta, slskd | 4747, 5274, 5030–5031, 50300 |
| `owntracks` | otrecorder, frontend | 8083, 8084 |
| `paperless-ngx` | redis, webserver | 8000 |
| `readmeabook` | readmeabook, readmeabook-mom | 3030, 3029 |
| `syncthing` | syncthing | 8384, 22000 (TCP/UDP), 21027 (UDP) |
| `wallabag` | postgres, redis, wallabag | 8001 |
