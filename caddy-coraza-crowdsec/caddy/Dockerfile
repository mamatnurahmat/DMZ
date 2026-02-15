FROM caddy:2.9-builder AS builder

WORKDIR /app
RUN xcaddy build \
    --with github.com/corazawaf/coraza-caddy/v2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@main \
    --with github.com/hslatman/caddy-crowdsec-bouncer/appsec@main

FROM caddy:2.9

COPY --from=builder /app/caddy /usr/bin/caddy