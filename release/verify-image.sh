#!/bin/sh
# Release gate for the ruTorrent 3.10 image with the rebuilt php7.2.
#
# Usage: release/verify-image.sh <image> [<registry>/<repository>:<tag>]
#
# Runs every check against the local <image>, which may be a local-only tag
# such as local/rutorrent-3.10-11-candidate:<commit>. Exits 0 only when the
# image passes every check and the registry definitively reports that the
# release tag (the second argument, or <image> when it is omitted) does not
# exist yet. Any indeterminate registry answer fails.
set -eu

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ "$#" -eq 1 ] || [ "$#" -eq 2 ] || fail "usage: $0 <image> [<registry>/<repository>:<tag>]"
image_ref=$1
release_ref=${2:-$1}
for ref in "$image_ref" "$release_ref"; do
    case "$ref" in
        ''|*[!A-Za-z0-9._/:-]*|*@*) fail "invalid image reference: $ref" ;;
    esac
done
release_dir=$(cd "$(dirname "$0")" && pwd)

echo "== PHP packages"
fpm_version=$(docker run --rm --network none --entrypoint php-fpm7.2 "$image_ref" -v | head -1)
echo "$fpm_version"
case "$fpm_version" in
    *+cylo*) ;;
    *) fail "php-fpm7.2 is not the locally rebuilt package" ;;
esac
packages=$(docker run --rm --network none --entrypoint dpkg-query "$image_ref" \
    -W -f='${Status}|${Package} ${Version}\n' 'php7.2-*' \
    | sed -n 's/^install ok installed|//p')
echo "$packages"
[ -n "$packages" ] || fail "no php7.2 packages installed"
if echo "$packages" | grep -v '+cylo' | grep -q .; then
    fail "some php7.2 packages are not from the local rebuild"
fi

echo "== FPM modules"
docker run --rm --network none --entrypoint php-fpm7.2 "$image_ref" -m \
    | diff -u "$release_dir/expected-fpm-modules.txt" - \
    || fail "FPM module list differs from the deployed image"

echo "== FPM configuration"
docker run --rm --network none --entrypoint php-fpm7.2 "$image_ref" -t \
    || fail "php-fpm7.2 configuration test failed"

echo "== Multipart upload"
docker run --rm --network none -v "$release_dir:/release:ro" --entrypoint sh "$image_ref" \
    /release/multipart-smoke.sh \
    || fail "multipart upload smoke test failed"

echo "== Regression checks"
for check in "$release_dir"/regression/*.sh; do
    [ -e "$check" ] || continue
    echo "-- $(basename "$check")"
    docker run --rm --network none -v "$release_dir:/release:ro" --entrypoint sh "$image_ref" \
        "/release/regression/$(basename "$check")" \
        || fail "regression check $(basename "$check") failed"
done

echo "== Registry tag must not exist"
registry=${release_ref%%/*}
repository_and_tag=${release_ref#*/}
repository=${repository_and_tag%:*}
tag=${repository_and_tag##*:}
[ "$repository" != "$repository_and_tag" ] || fail "image reference has no tag"

registry_auth=$(jq -r --arg host "$registry" '.auths[$host].auth // empty' "$HOME/.docker/config.json")
[ -n "$registry_auth" ] || fail "no stored credentials for $registry"

registry_body=$(mktemp)
trap 'rm -f "$registry_body"' EXIT

registry_get() {
    printf 'header = "Authorization: Basic %s"\n' "$registry_auth" \
        | curl -sS -K - -o "$registry_body" -w '%{http_code}' \
            -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
            "https://$registry$1"
}

api_status=$(registry_get /v2/) || fail "registry unreachable"
[ "$api_status" = 200 ] || fail "registry API check returned HTTP $api_status"

manifest_status=$(registry_get "/v2/$repository/manifests/$tag") || fail "registry unreachable"
case "$manifest_status" in
    200) fail "$release_ref already exists in the registry" ;;
    404)
        grep -q 'MANIFEST_UNKNOWN' "$registry_body" \
            || fail "registry returned 404 without MANIFEST_UNKNOWN: $(head -c 300 "$registry_body")"
        echo "$release_ref is not in the registry yet"
        ;;
    *) fail "registry returned HTTP $manifest_status for $release_ref" ;;
esac

echo "PASS: $image_ref (release tag $release_ref)"
