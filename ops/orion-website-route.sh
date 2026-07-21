#!/bin/sh
set -eu

deployment_root="/opt/orion-website"
orion_current="$(readlink -f /opt/orion/current)"
orion_caddyfile="$orion_current/deploy/production/Caddyfile"
combined_caddyfile="$deployment_root/shared/combined.Caddyfile"

test -f "$orion_caddyfile"
docker container inspect orion-website >/dev/null 2>&1 || exit 0

caddy_container="$(
  docker ps \
    --filter 'label=com.docker.compose.project=orion-development' \
    --filter 'label=com.docker.compose.service=caddy' \
    --format '{{.Names}}'
)"
test -n "$caddy_container"
test "$(printf '%s\n' "$caddy_container" | wc -l)" -eq 1

mkdir -p "$deployment_root/shared"
cp "$orion_caddyfile" "$combined_caddyfile"
cat >> "$combined_caddyfile" <<'CADDY'

orion.charsi-marketplace.com {
    encode zstd gzip
    reverse_proxy orion-website:80

    header {
        Strict-Transport-Security "max-age=31536000"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=()"
    }
}
CADDY

docker cp "$combined_caddyfile" "$caddy_container:/tmp/orion-combined.Caddyfile"
docker exec "$caddy_container" caddy validate --config /tmp/orion-combined.Caddyfile >/dev/null
docker exec "$caddy_container" caddy reload --config /tmp/orion-combined.Caddyfile >/dev/null
