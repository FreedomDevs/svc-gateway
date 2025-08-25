# svc-gateway

## Сборка в Docker
```
docker build . -t svc-gateway:latest
docker run --rm -v $(pwd)/config.yml:/config.yml:ro svc-gateway:latest
```
