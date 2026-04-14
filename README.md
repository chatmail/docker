# Docker installation

This repository contains the Docker setup for [chatmail relay](https://github.com/chatmail/relay).

> **Note**
> - Docker support is experimental, CI builds and tests the image automatically, but please report bugs.
> - The image wraps the cmdeploy process in a Debian-systemd image with r/w access to `/sys/fs`
> - Currently amd64-only (arm64 should work but is untested).

## Getting started

Clone the relay repo and add this repository as a submodule:

```bash
git clone https://github.com/chatmail/relay
cd relay
git submodule add https://github.com/chatmail/docker docker
cd docker
```

## Setup Preparation

We use `chat.example.org` as the chatmail domain in the following
steps. Please substitute it with your own domain.

1. Install docker and docker compose v2 (check with `docker compose version`), install, e.g., on
    - Debian 12 through the [official install instructions](https://docs.docker.com/engine/install/debian/#install-using-the-repository)
    - Debian 13+ with `apt install docker docker-compose`

2. Setup the initial DNS records.
   The following is an example in the familiar BIND zone file format with
   a TTL of 1 hour (3600 seconds).
   Please substitute your domain and IP addresses.

   ```
   chat.example.org. 3600 IN A 198.51.100.5
   chat.example.org. 3600 IN AAAA 2001:db8::5
   www.chat.example.org. 3600 IN CNAME chat.example.org.
   mta-sts.chat.example.org. 3600 IN CNAME chat.example.org.
   ```

3. Configure kernel parameters on the host, as these can not be set from the container:

   ```bash
   echo "fs.inotify.max_user_instances=65536" | sudo tee -a /etc/sysctl.d/99-inotify.conf
   echo "fs.inotify.max_user_watches=65536" | sudo tee -a /etc/sysctl.d/99-inotify.conf
   sudo sysctl --system
   ```

## Docker Compose Setup

Pre-built images are available from GitHub Container Registry. The
`main` branch and tagged releases are pushed automatically by CI:

```bash
docker pull ghcr.io/chatmail/relay:main      # latest main branch
docker pull ghcr.io/chatmail/relay:1.2.3     # tagged release
```

### Create service directory

Either:

- Create a service directory and download the compose files:

  ```bash
  mkdir -p /srv/chatmail-relay && cd /srv/chatmail-relay
  wget https://raw.githubusercontent.com/deltachat/docker/refs/heads/main/docker-compose.yaml
  wget https://raw.githubusercontent.com/deltachat/docker/refs/heads/main/docker-compose.override.yaml.example -O docker-compose.override.yaml
  ```

- or clone the docker repo directly:

  ```bash
  git clone https://github.com/deltachat/docker
  cd docker
  ```

### Customize and start

1. Set the fully qualified domain name of the relay:

   ```bash
   echo 'MAIL_DOMAIN=chat.example.org' > .env
   ```

   The container generates a `chatmail.ini` with defaults from
   `MAIL_DOMAIN` on first start. To customize chatmail settings, mount
   your own `chatmail.ini` instead (see [Custom chatmail.ini](#custom-chatmailiini) below).

2. All local customizations (data paths, extra volumes, config mounts) go in
   `docker-compose.override.yaml`, which Compose merges automatically with
   the base file. By default, all data is stored in docker volumes, you will
   likely want to at least create and configure the mail storage location, but
   you might also want to configure external TLS certificates there.

3. Start the container:

   ```bash
   docker compose up -d
   docker compose logs -f chatmail   # view logs, Ctrl+C to exit
   ```

4. After installation is complete, open `https://chat.example.org` in
   your browser.

## Finish install and test

You can test the installation with:

```bash
pip install cmping
cmping chat.example.org
# or
uvx cmping chat.example.org # if you use https://docs.astral.sh/uv/
```

You should check and extend your DNS records for better interoperability:

```bash
# Show required DNS records
docker exec chatmail cmdeploy dns --ssh-host @local
```

You can check server status with:

```bash
docker exec chatmail cmdeploy status --ssh-host @local
```

You can run some benchmarks (can also run from any machine with cmdeploy installed):

```bash
docker exec chatmail cmdeploy bench
```

You can run the test suite with:

```bash
docker exec chatmail cmdeploy test --ssh-host localhost
```

You can look at logs:

```bash
docker exec chatmail journalctl -fu postfix@-
```

## Customization

### Website

You can customize the chatmail landing page by mounting a directory with
your own website source files.

1. Create a directory with your custom website source:

   ```bash
   mkdir -p ./custom/www/src
   nano ./custom/www/src/index.md
   ```

2. Add the volume mount in `docker-compose.override.yaml`:

   ```yaml
   services:
     chatmail:
       volumes:
         - ./custom/www:/opt/chatmail-www
   ```

3. Restart the service:

   ```bash
   docker compose down
   docker compose up -d
   ```

### Custom chatmail.ini

If you want to go beyond simply setting the `MAIL_DOMAIN` in `.env`, you
can use a regular `chatmail.ini` to give you full control.

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

If TLS certificates are managed outside the container (e.g. by certbot,
acmetool, or Traefik on the host), mount them into the container and set
`TLS_EXTERNAL_CERT_AND_KEY` in `docker-compose.override.yaml`.
Changed certificates are picked up automatically via inotify.
See the examples in the example override and the Getting Started guide for details.

## Migrating from a bare-metal install

If you have an existing bare-metal chatmail installation and want to
switch to Docker:

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
