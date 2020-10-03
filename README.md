# What

Docker image for ElasticSearch.

This is based on [Elastic](https://github.com/elastic/elasticsearch).

## Image features

 * multi-architecture:
    * [x] linux/amd64
    * [ ] ~~linux/arm64~~ unsupported by Elastic
    * [ ] ~~linux/arm/v7~~ unsupported by Elastic
    * [ ] ~~linux/arm/v6~~ unsupported by Elastic
 * hardened:
    * [x] image runs read-only
    * [x] image runs with no capabilities
    * [x] process runs as a non-root user, disabled login, no shell
 * lightweight
    * [x] based on our slim [Debian buster version](https://github.com/dubo-dubon-duponey/docker-debian)
    * [x] simple entrypoint script
    * [x] multi-stage build with no installed dependencies for the runtime image
 * observable
    * [x] healthcheck
    * [x] log to stdout
    * [ ] ~~prometheus endpoint~~ not applicable

## Run

```bash
docker run -d \
    --net bridge \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/elastic
```

## Notes

### Prometheus

Not applicable.

## Moar?

See [DEVELOP.md](DEVELOP.md)
