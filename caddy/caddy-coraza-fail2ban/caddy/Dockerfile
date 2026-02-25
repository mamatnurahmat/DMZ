FROM caddy:2.9-builder AS builder

WORKDIR /app
RUN xcaddy build \
    --with github.com/corazawaf/coraza-caddy/v2

FROM caddy:2.9

COPY --from=builder /app/caddy /usr/bin/caddy