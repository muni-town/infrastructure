# Muni Town Small Server Template

This is the base server template used at Muni Town for some our small cloud servers.

Right now we use Digital Ocean for hosting, and we use [Flatcar](https://www.flatcar.org/) for the OS.

See [Provisioning a New Server](#provisioning-a-new-server) for a completely deployment walkthrough.

## Setup Overview

We manage all of our apps with [Docker] and the [Portainer] web UI. We use Portainer to manage our
[Docker compose][dc] stacks.

Our server template has what we call the "docker compose core stack" located on the server at
`/docker-compose-core-stack`. This stack is run at startup and contains the [Traefik], [Portainer],
and [Restic] services.

- **[Traefik]** is our reverse proxy responsible for routing _all_ incoming HTTP traffic on the
  machine. It integrates with docker and generates our HTTPS certificates.
- **[Portainer]** is our web management UI which we use to create and manage [docker compose][dc]
  application stacks.
- **[Restic]** is our backup tool which we use to backup our docker volumes on schedule.

To manage the stack you must be `root`, so after ssh-ing into the server as the `core` user you can
get to the stack by:

```bash
sudo su -
cd /docker-compose-core-stack
# Now you can manage the stack with docker compose
docker compose ps
```

The core stack is the one stack that you cannot manage in Portainer, because it exists before
Portainer does.

### Docker Volumes

For management simplicity and to make it simple to backup, all persistent docker volumes in any of
the stacks should store their volumes by convention as bind mounts to
`/docker-volumes/stack-name/volume-name`.

### Backups

The [Restic] service will daily backup the docker volumes and is configured to keep the latest 7 daily
backups, 5 weekly backups, 12 monthly backups, and 75 yearly backups. It uses incremental backups to
make this space and compute efficient.

In the current config, backups are stored at `/backups` on the server, but that is not that useful
if the entire server is destroyed. In a production environment backups should be stored on S3 or a
similar remote storage. This is easily configured in Restic.

> **Important Note:** If you have a database like Postgres or MySQL running in a docker stack, you
> may store it's data in the `/docker-volumes` dir like the rest of the volumes, but the snapshot
> that restic makes of that directory is **not** considered a safe way to backup a SQL database.
>
> One possible solution is to use a container that runs alongside your database and periodically
> exports SQL dumps to another volume in the `/docker-volumes` dir. That way the SQL dump will be
> backed up by restic and your database will have stable backups.
>
> There are other more production-grade backup solutions for databases that you should consider.

### The `webgateway` Network & Traefik Routing

In order for the Traefik container to route network traffic to any containers that you want to
expose to the internet, those containers have to be on the same network as the Traefik container.

The `webgateway` network is a docker network created specifically for Traefik and any services that
Traefik needs to route to. For example, here is an example of an exposed web service. You can add
this YAML as a stack in Portainer to test it.

```yaml
services:
  nginx:
    image: nginx
    restart: unless-stopped
    networks:
      - webgateway
    labels:
      # NOTE: You have to replace my.management.domain with your management domain
      #       that you have configured in the .env file.
      - traefik.http.routers.rtr-example.rule=Host(`example.my.management.domain`)
      - traefik.http.routers.rtr-example.tls=true
      - traefik.http.routers.rtr-example.tls.certResolver=letsencrypt
      - traefik.http.services.srv-example.loadbalancer.server.port=80
      
networks:
  webgateway:
    # This is necessary to tell compose that the network
    # we are connecting to is not defined in this stack
    # but that it does exist in Docker.
    external: true
```

> **Note:** In that example we use a sub-domain of our management domain because we have already
> configured a wildcard DNS record that allows us to easily add services with domains that are
> a subdomain of our management domain.
>
> If you want to host under a different domain that is entirely possible, you just need to make sure
> that you point your DNS to your server before adding the Traefik labels so that Traefik can
> automatically generate the certificate.

### .env Configuration

There is a [`.env.example`](./.env.example) that you copy to `.env` and that is copied to
`/docker-compose-core-stack` to add env vars used by Docker compose.

### Traefik Dashboard

The Traefik dashboard shows Traefik's discovered configuration and can be useful for debugging. It
is hosted at `traefik.MANAGEMENT_DOMAIN` where the management domain is configured in the `.env`
file.

The dashboard is protected from public access with a `traefik-dash-auth` middleware that uses basic
HTTP auth. The username and password is configured with the `TRAEFIK_DASHBOARD_HTPASSWD` env var in
the `.env` file.

It's value should be an `htpasswd` formatted username and password. You can generate a value in the
correct format by using the `htpasswd` CLI tool or running:

```
docker run --rm -it xmartlabs/htpasswd [myusername] [mypassword]
```

The `traefik-dash-auth` middleware can also be used for other containers in other stacks if you
would like to easily add some authentication to an admin dashboard, for instance. You can add the
middleware using the traefik config in your docker labels ( see [traefik
docs](https://doc.traefik.io/traefik/middlewares/overview/) ):

```yaml
labels:
  # ...other traefik labels, see traefik docs
  - traefik.http.routers.my-traefik-router-name.middlewares=traefik-dash-auth
```

### Traefik Dashboard

The traefik config has a basic auth middleware setup so that you can get to the

[Docker]: https://docker.com
[Portainer]: https://www.portainer.io/
[dc]: https://docs.docker.com/compose/
[Traefik]: https://doc.traefik.io/
[Restic]: https://restic.net/

## Provisioning a New Server

Here are the steps to provision a new server.

### Upload Flatcar Image to Digital Ocean

If you have not yet done so, you need to upload the Flatcar linux image to digital ocean.

> **Note:** The official Flatcar documentation for using Flatcar on Digital Ocean can be found [here][dof].

1. Go to the DO ( Digital Ocean ) dashboard.
2. Go to "Backups & Snapshots" in the left sidebar.
3. Go to the "Custom Images" tab.
4. Click "Import Via URL".

You need to paste in the flatcar image URL which will be in the format:

    https://<channel>.release.flatcar-linux.net/amd64-usr/<version>/flatcar_production_digitalocean_image.bin.bz2

For example, at the time of writing the latest stable version is:

    https://stable.release.flatcar-linux.net/amd64-usr/4230.2.1/flatcar_production_digitalocean_image.bin.bz2

You will have to select a name and region before confirming and DO should download the image for you.

[dof]: https://www.flatcar.org/docs/latest/installing/cloud/digitalocean/

### Generating the Ignition Config

1. Download the latest release ( 0.24.0 at the time of writing ) of Butane from the [github releases][bgr].
2. Copy the `.env.example` file to `.env` and make changes to configure the deployment.
3. Select a `MANAGEMENT_DOMAIN` domain that you have DNS control of and take note of it.
4. Run `butane butane.yaml -d . > ignition.json` in this repo to generate the ignition JSON config.

[bgr]: https://github.com/coreos/butane/releases

### Creating A Droplet

1. Go to the DO dashboard.
2. Click the "Create" button and select "Droplets".
3. Select a region. This must be a region that you have uploaded your Flatcar linux image to.
4. Select the "Custom Images" tab in the "Choose an Image" section and pick your uploaded Flatcar image.
5. Select a droplet size as normal.
6. Expand the "Advanced Options" section and select "Add Initialization Scripts ( free )".
7. Paste in the contents of the `ignition.json` file created in the above.
8. Select a hostname and confirm droplet creation.

### DNS Setup

1. Configure the `MANAGEMENT_DOMAIN` that you selected in the `.env` file to point to the IP address
   of your droplet.
2. You will need to create two `A` records, one for the management domain you specified, and another
   wildcard domain. For example if your management domain is `example.org` you need an `A` record
   for `example.org` and `*.example.org`.

### Final Setup

1. Verify that you can SSH into the machine.

> **Note:** Right now only Zicklag's public key is authorized to SSH into the server. If you need to
> add other authorized keys youc an do that in the butane.yaml.

2. Traefik should generate the certificates so that you can hit the portainer web UI at
   `https://portainer.MANAGEMENT_DOMAIN`. You may need to restart traefik if it doesn't generate
   certs within a short time.
3. You can ssh into the server by running `ssh core@MANAGEMENT_DOMAIN`.
4. You can use `sudo su -` to become `root` and then `cd /docker-compose-core-stack` to get to the
   folder with the docker compose stack containing Traefik, Portainer, and Restic.
5. You can do `docker compose restart` to restart all the services or `docker compose restart
traefik` to restart a specific service.
6. Once traefik generates the certs, the Portainer first time install timer may have expired so you
   may have to run: `docker compose restart portainer`.
7. Set the portainer admin username and password and you are ready to go! 🚀

### Enable Improved DO Metrics ( Optional )

You may also want to run the digital ocean metrics agent to get improved graphs for your droplet in
the DO dashboard. You can do that by running:

```bash
docker run                      \
   -v /proc:/host/proc:ro       \
   -v /sys:/host/sys:ro         \
   -d --name do-agent           \
   --restart unless-stopped     \
   digitalocean/do-agent:stable
```

That's it! That container will log the server metrics to the DO dashboard and can easily be removed
at any time if you wish.
