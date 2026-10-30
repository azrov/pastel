# Deploying to a Linux server

Three ways, from simplest to most packaged. All of them start with a
release build from `pastel package`; the program is one file and needs no
runtime on the server.

| | Use it when |
|---|---|
| `pastel package` | copying a folder is enough: `.tar.gz` with the program and its files |
| `pastel package deb` | Debian, Ubuntu, Raspberry Pi OS servers: `apt install`, systemd, upgrades |
| `pastel package docker` | the server runs containers (Docker, Podman, Kubernetes) |

## A .deb

```sh
pastel package deb                       # dist/myapi_0.1.0_amd64.deb
pastel package deb --target linux-arm64  # dist/myapi_0.1.0_arm64.deb (Raspberry Pi 4/5)
pastel package deb --all                 # every Linux platform in pastel.toml
```

On the server:

```sh
sudo apt install ./myapi_0.1.0_amd64.deb
sudo nano /etc/myapi/config.toml         # real API keys, the database
sudo systemctl start myapi
journalctl -u myapi -f
```

What goes where:

| | |
|---|---|
| `/opt/myapi/` | the program, README, and what `[package] include` lists (migrations too) |
| `/usr/lib/systemd/system/myapi.service` | `deploy/myapi.service` (services) |
| `/etc/myapi/config.toml` | `config.example.toml` (services); kept on upgrades when you changed it |
| `/var/lib/myapi/` | the service's data (the SQLite database), made by systemd |
| `/usr/bin/myapi` | a link to the program (console programs and apps) |

The service is enabled on install but not started, so you can set it up
first; an upgrade (`apt install` of a newer .deb) restarts it if it was
running. `apt remove myapi` stops it; the data in `/var/lib` stays.

`pastel.toml`:

```toml
[project]
description = "The shop's order API"

[package]
maintainer = "Ayşe Yılmaz <ayse@example.com>"

[package.deb]
depends = ["libsqlite3-0"]     # libpq5 for PostgreSQL, libmariadb3 for MySQL/MariaDB
```

The .deb is made by Pastel itself, so it can be made on Windows and macOS
too. An API whose settings still have the example API key
(`CHANGE-ME-...`) does not start: it says so in the journal.

## A container image

```sh
pastel package docker              # builds the image myapi:0.1.0 (and :latest)
pastel package docker --no-build   # only dist/docker-linux/ with the Dockerfile
docker run -p 8080:8080 -e MYAPI_API_KEYS=$(openssl rand -hex 32) -v myapi-data:/var/lib/myapi myapi
```

The image is Debian slim (`[package.docker] base = "..."` for another)
with the packages of `[package.deb] depends`. The program runs as a user
without rights, logs JSON to the container's output, listens on all
addresses (port 8080) and has a health check. Settings come from
environment variables: `MYAPI_DATABASE_URL=postgres://...`,
`MYAPI_API_KEYS=key1,key2`, `MYAPI_LOG_LEVEL=debug`. `docker stop` stops it
cleanly.

## HTTPS: a reverse proxy in front

The Pastel web server speaks plain HTTP and listens on `127.0.0.1`; a
reverse proxy on the same machine adds HTTPS and the domain name.

**Caddy** (gets the certificate by itself), `/etc/caddy/Caddyfile`:

```
api.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

**nginx**, with a certificate from `certbot --nginx`:

```nginx
server {
    server_name api.example.com;
    client_max_body_size 10m;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
    }
}
```

Then set `[server] trust_proxy = true`, so client addresses (logs, rate
limits) come from the proxy's `X-Forwarded-For` ([web.md](web.md)).

## Checklist

- Real secrets in `/etc/myapi/config.toml` or the environment, never in the code or the image.
- `[server] address = "127.0.0.1"` behind a proxy; the firewall opens only 80 and 443.
- `/health` for monitoring.
- Backups of `/var/lib/myapi` (SQLite: `sqlite3 app.db ".backup backup.db"` while it runs) or of the database server.
- Services and systemd in detail: [services.md](services.md).
