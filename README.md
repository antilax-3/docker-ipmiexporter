[logo]: https://ci.nerv.com.au/userContent/antilax-3.png "AntilaX-3"
[![alt text][logo]](https://github.com/AntilaX-3/)

# AntilaX-3/ipmi-exporter
[![](https://images.microbadger.com/badges/version/antilax3/ipmi-exporter.svg)](https://microbadger.com/images/antilax3/ipmi-exporter "Get your own version badge on microbadger.com") [![](https://images.microbadger.com/badges/image/antilax3/ipmi-exporter.svg)](https://microbadger.com/images/antilax3/ipmi-exporter "Get your own image badge on microbadger.com") [![Docker Pulls](https://img.shields.io/docker/pulls/antilax3/ipmi-exporter.svg)](https://hub.docker.com/r/antilax3/ipmi-exporter/) [![Docker Stars](https://img.shields.io/docker/stars/antilax3/ipmi-exporter.svg)](https://hub.docker.com/r/antilax3/ipmi-exporter/)

[ipmi-exporter](https://github.com/lovoo/ipmi_exporter) is a simple server that periodically scrapes IPMI stats and exports them via HTTP for Prometheus consumption, written in Go. 
## Usage
```
docker create --name=ipmiexporter \
--device=/dev/ipmi0:/dev/ipmi0 \
-p 9289:9289 \
antilax3/ipmi-exporter
```
## Parameters
The parameters are split into two halves, separated by a colon, the left hand side representing the host and the right the container side. For example with a volume -v external:internal - what this shows is the volume mapping from internal to external of the container. So -v /mnt/app/config:/config would map /config from inside the container to be accessible from /mnt/app/config on the host's filesystem.

- `-p 9289` - HTTP port for webserver
- `-e PUID` - for UserID, see below for explanation
- `-e PGID` - for GroupID, see below for explanation
- `-e TZ` - for setting timezone information, eg Australia/Melbourne

It is based on alpine linux with s6 overlay, for shell access whilst the container is running do `docker exec -it ipmiexporter /bin/bash`.

## User / Group Identifiers
Sometimes when using data volumes (-v flags) permissions issues can arise between the host OS and the container. We avoid this issue by allowing you to specify the user `PUID` and group `PGID`. Ensure the data volume directory on the host is owned by the same user you specify and it will "just work".

In this instance `PUID=1001` and `PGID=1001`. To find yours use `id user` as below:
`$ id <dockeruser>`
    `uid=1001(dockeruser) gid=1001(dockergroup) groups=1001(dockergroup)`
    
## Configuration

To ensure that ipmi-exporter can retrieve and expose metrics you need to mount your IPMI device in the container, per the usage example above or for docker-compose example below:

```yaml
  ipmiexporter:
    image: ipmi-exporter
    container_name: ipmiexporter
    devices:
      - /dev/ipmi0:/dev/ipmi0
    restart: unless-stopped
    ports:
      - 9289:9289
```

## Version
- **17/04/19:** Initial Release