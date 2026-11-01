# Running salon-api on a Linux server

The easiest on Debian, Ubuntu and Raspberry Pi OS is a package:

```sh
pastel package deb                      # dist/salon-api_0.1.0_amd64.deb
scp dist/salon-api_0.1.0_amd64.deb you@server:
ssh you@server
sudo apt install ./salon-api_0.1.0_amd64.deb
sudo nano /etc/salon-api/config.toml     # real API keys, the database
sudo systemctl start salon-api
```

Or a container image: `pastel package docker`. Both: docs/deploy.md of Pastel.

By hand, on your computer:

```sh
pastel package                          # dist/salon-api-0.1.0-linux.tar.gz
pastel package --target linux-arm64     # for a Raspberry Pi or an ARM server
scp dist/salon-api-0.1.0-linux.tar.gz you@server:
```

On the server:

```sh
tar -xzf salon-api-0.1.0-linux.tar.gz
sudo mv salon-api-0.1.0-linux /opt/salon-api
sudo mkdir -p /etc/salon-api
sudo cp /opt/salon-api/config.example.toml /etc/salon-api/config.toml
sudo cp /opt/salon-api/deploy/salon-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now salon-api
```

Then:

```sh
systemctl status salon-api               # is it running?
journalctl -u salon-api -f               # its log, live
journalctl -u salon-api -p err           # only errors
sudo systemctl reload salon-api          # after editing /etc/salon-api/config.toml
sudo systemctl restart salon-api         # after installing a new version
```

The SQLite database (when used) is `/var/lib/salon-api/app.db`; put nginx or Caddy in front for HTTPS (docs/web.md).
