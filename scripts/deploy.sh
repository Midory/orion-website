#!/bin/sh
set -eu

release_sha="${1:?Pass the validated release SHA}"
deployment_root="${WEBSITE_DEPLOYMENT_ROOT:-/opt/orion-website}"
public_url="${WEBSITE_PUBLIC_URL:-https://orion.charsi-marketplace.com}"
public_host="${public_url#https://}"
public_host="${public_host%%/*}"
release_dir="$deployment_root/releases/$release_sha"
current_link="$deployment_root/current"
container_name="orion-website"
network_name="orion-development_edge"
nginx_image="nginx:1.29-alpine@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de"

printf '%s' "$release_sha" | grep -Eq '^[0-9a-f]{40}$'
test -d dist
test "$(find dist -mindepth 1 -maxdepth 1 | wc -l)" -gt 0

mkdir -p "$deployment_root/releases" "$deployment_root/shared"
if test ! -d "$release_dir"; then
  staging_dir="$deployment_root/releases/.staging-$release_sha-${GITHUB_RUN_ID:-$$}"
  test ! -e "$staging_dir"
  mkdir "$staging_dir"
  cp -R dist/. "$staging_dir/"
  chmod -R a=rX "$staging_dir"
  mv "$staging_dir" "$release_dir"
fi

next_link="$deployment_root/.current-$release_sha"
ln -s "$release_dir" "$next_link"
mv -Tf "$next_link" "$current_link"
printf '%s\n' "$release_sha" > "$deployment_root/shared/deployed-sha"

docker network inspect "$network_name" >/dev/null
if docker container inspect "$container_name" >/dev/null 2>&1; then
  docker rm -f "$container_name" >/dev/null
fi
docker run -d \
  --name "$container_name" \
  --network "$network_name" \
  --restart unless-stopped \
  --read-only \
  --tmpfs /var/cache/nginx:rw,noexec,nosuid,size=16m \
  --tmpfs /var/run:rw,noexec,nosuid,size=1m \
  --mount "type=bind,src=$release_dir,dst=/usr/share/nginx/html,readonly" \
  "$nginx_image" >/dev/null

docker exec "$container_name" wget -qO- http://127.0.0.1/ >/dev/null
/usr/local/sbin/orion-website-route

# Verify the public hostname, certificate and reverse-proxy route without being
# held hostage by a stale recursive DNS cache on the deployment host.
attempt=0
until curl --fail --silent --show-error --max-time 10 \
  --resolve "$public_host:443:127.0.0.1" "$public_url/" >/dev/null; do
  attempt=$((attempt + 1))
  test "$attempt" -lt 12
  sleep 5
done

printf 'Deployed Orion website %s to %s\n' "$release_sha" "$public_url"
