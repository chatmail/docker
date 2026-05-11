# Docker installation

This repository contains the Docker setup for [chatmail relay](https://github.com/chatmail/relay).

> **Note**
> - Docker support is experimental, CI builds and tests the image automatically, but please report bugs.
> - The image wraps the cmdeploy process in a Debian-systemd image with r/w access to `/sys/fs`
> - Currently amd64-only (arm64 should work but is untested).

### Pre-built image

Pre-built images are available from GitHub Container Registry. The `main` branch and
tagged releases are pushed automatically by CI:

```bash
docker pull ghcr.io/chatmail/docker:main      # latest main branch
docker pull ghcr.io/chatmail/docker:1.2.3     # tagged release
```

Install instructions follow for use with Docker Compose.

## Prerequisites

### 1. Install Docker and Docker Compose v2

Check your version with:
```bash
docker compose version
```

Install on:
- **Debian 12** via [official install instructions](https://docs.docker.com/engine/install/debian/#install-using-the-repository)
- **Debian 13+** with `apt install docker docker-compose`

### 2. Configure kernel parameters

These must be set on the host, as they cannot be set from the container:

```bash
echo "fs.inotify.max_user_instances=65536" | sudo tee -a /etc/sysctl.d/99-inotify.conf
echo "fs.inotify.max_user_watches=65536" | sudo tee -a /etc/sysctl.d/99-inotify.conf
sudo sysctl --system
```

### 3. Setup DNS records

The following is an example in BIND zone file format with a TTL of 1 hour (3600 seconds).
Substitute `chat.example.org` with your domain and update IP addresses:

```
chat.example.org. 3600 IN A 198.51.100.5
chat.example.org. 3600 IN AAAA 2001:db8::5
www.chat.example.org. 3600 IN CNAME chat.example.org.
mta-sts.chat.example.org. 3600 IN CNAME chat.example.org.
```

## Installation

### Create service directory

Choose one approach:

**Option A: Download compose files directly**

```bash
mkdir -p /srv/chatmail-relay && cd /srv/chatmail-relay
wget https://raw.githubusercontent.com/chatmail/docker/main/docker-compose.yaml
wget https://raw.githubusercontent.com/chatmail/docker/main/docker-compose.override.yaml.example -O docker-compose.override.yaml
```

**Option B: Clone the docker repo**

```bash
git clone https://github.com/chatmail/docker
cd docker
```

### Configure and start

1. Set the fully qualified domain name (use `chat.example.org` or your own domain):

   ```bash
   echo 'MAIL_DOMAIN=chat.example.org' > .env
   ```

   The container generates a `chatmail.ini` with defaults from `MAIL_DOMAIN` on first start.
   To customize chatmail settings, mount your own `chatmail.ini` instead
   (see [Custom chatmail.ini](#custom-chatmailiini) below).

2. Configure local customizations in `docker-compose.override.yaml`:

   By default, all data is stored in docker volumes. You'll likely want to:
   - Create and configure the mail storage location
   - Configure external TLS certificates (if not using auto-generated certs)
   - Customize the website

   See the [Customization](#customization) section for examples.

3. Start the container:

   ```bash
   docker compose up -d
   docker compose logs -f chatmail   # view logs, Ctrl+C to exit
   ```

4. After installation is complete, open `https://chat.example.org` in your browser.

## Testing and finishing

### Test the installation

```bash
pip install cmping
cmping chat.example.org
# alternatively, if you use https://docs.astral.sh/uv/
uvx cmping chat.example.org
```

### Check and extend DNS records

Show required DNS records:

```bash
docker exec chatmail cmdeploy dns --ssh-host @local
```

### Check server status

```bash
docker exec chatmail cmdeploy status --ssh-host @local
```

### Run benchmarks

```bash
docker exec chatmail cmdeploy bench
```

### Run the test suite

```bash
docker exec chatmail cmdeploy test --ssh-host localhost
```

### View logs

```bash
docker exec chatmail journalctl -fu postfix@-
```

## Customization

### Website

Customize the chatmail landing page by mounting a directory with your own website source.

1. Create a directory with your custom website source:

   ```bash
   mkdir -p ./data/www/src
   nano ./data/www/src/index.md
   ```

2. Add the volume mount in `docker-compose.override.yaml`:

   ```yaml
   services:
     chatmail:
       volumes:
         - ./data/www:/opt/chatmail-www
   ```

3. Restart the service:

   ```bash
   docker compose down
   docker compose up -d
   ```

### Custom chatmail.ini

For full control over chatmail settings beyond just `MAIL_DOMAIN`:

1. Extract the generated config from a running container:

   ```bash
   docker cp chatmail:/etc/chatmail/chatmail.ini ./chatmail.ini
   ```

2. Edit `chatmail.ini` as needed.

3. Add the volume mount in `docker-compose.override.yaml`:

   ```yaml
   services:
     chatmail:
       volumes:
         - ./chatmail.ini:/etc/chatmail/chatmail.ini
   ```

4. Restart the container:

   ```bash
   docker compose down && docker compose up -d
   ```

### External TLS certificates

If TLS certificates are managed outside the container (e.g., by certbot, acmetool, or Traefik
on the host), mount them into the container and set `TLS_EXTERNAL_CERT_AND_KEY`
in `docker-compose.override.yaml`.

Changed certificates are picked up automatically via inotify. See the examples in
`docker-compose.override.yaml.example` for details.

## Migrating from a bare-metal install

If you have an existing bare-metal chatmail installation and want to switch to Docker:

1. Stop all existing services:

   ```bash
   systemctl stop postfix dovecot doveauth nginx opendkim unbound \
     acmetool-redirector filtermail filtermail-incoming chatmail-turn \
     iroh-relay chatmail-metadata lastlogin mtail
   systemctl disable postfix dovecot doveauth nginx opendkim unbound \
     acmetool-redirector filtermail filtermail-incoming chatmail-turn \
     iroh-relay chatmail-metadata lastlogin mtail
   ```

2. Copy your existing `chatmail.ini` and mount it into the container
   (see [Custom chatmail.ini](#custom-chatmailiini) above):

   ```bash
   cp /usr/local/lib/chatmaild/chatmail.ini ./chatmail.ini
   ```

3. Copy persistent data into the `./data/` subdirectories:

   ```bash
   mkdir -p data/dkim data/certs data/mail
   
   # DKIM keys
   cp -a /etc/dkimkeys/* data/dkim/
   
   # TLS certificates
   rsync -a /var/lib/acme/ data/certs/
   ```

   Note that ownership of dkim and acme is adjusted on container start.

   For the mail directory:

   ```bash
   rsync -a /home/vmail/ data/mail/
   ```

   Alternatively, mount `/home/vmail` directly by changing the volume
   in `docker-compose.override.yaml`:

   ```yaml
   services:
     chatmail:
       volumes:
         - /home/vmail:/home/vmail
   ```

   The three `./data/` subdirectories cover all persistent state.
   Everything else is regenerated by the `configure` and `activate`
   stages on container start.

## Development / Contributing

Clone the relay repo and add this repository inside, then copy the `.dockerignore` and build:

```bash
git clone https://github.com/chatmail/relay
cd relay
git clone https://github.com/chatmail/docker
cd docker
cp .dockerignore ..
docker compose build
```
