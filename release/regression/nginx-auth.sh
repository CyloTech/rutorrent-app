#!/bin/sh
# nginx: every ruTorrent PHP endpoint needs the ruTorrent login.
#
# The site's PHP scripts are served by "location ~ \.php$", which does not
# inherit auth_basic from "location /". Without the fix, ruTorrent's settings,
# torrent upload, httprpc and rpc plugin endpoints answer without credentials,
# and PHP takes the user name from any Authorization header, so a wrong
# password is enough to act as that user.
#
# The check starts the image the way Appbox does (/scripts/start.sh with a
# test login; the install callback, which needs the network, is answered by
# a stub) and then, through nginx on 127.0.0.1:
#   1. sends GET and POST requests without credentials, and with a wrong
#      password, to the main page, /pid.php (a test script in the web root),
#      /php/setsettings.php, /php/addtorrent.php,
#      /plugins/httprpc/action.php, /plugins/rpc/rpc.php and /RPC2. Each must
#      return 401 with the "Restricted" Basic challenge and change nothing;
#   2. sends requests to the same endpoints with the test login, which must
#      work as before: the page loads, settings are saved, a torrent is
#      added and listed, and rTorrent answers XML-RPC;
#   3. requests every other PHP file in the web root without credentials,
#      which must return 401;
#   4. checks that the fileshare plugin's public link handler,
#      /no-auth/share.php, still runs without credentials.
set -eu

check_dir=$(mktemp -d /tmp/nginx-auth.XXXXXX)
html=/torrents/config/rutorrent/html
base=http://127.0.0.1
user=regression
password=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')
failures=0

fail() {
    echo "FAIL: $*" >&2
    for log in "$check_dir/start.log" /tmp/supervisord.log; do
        [ -f "$log" ] || continue
        echo "--- $log" >&2
        tail -n 30 "$log" >&2
    done
    exit 1
}

# Record a failed expectation and keep going, so one run shows every gap.
miss() {
    echo "  FAIL $*"
    failures=$((failures + 1))
}

# request <label> <expected status> <body pattern or -> <curl arguments...>
# The body pattern is a fixed string that the response body must contain.
request() {
    label=$1 expected=$2 pattern=$3
    shift 3
    status=$(/usr/bin/curl -s -o "$check_dir/body" -D "$check_dir/headers" \
        -w '%{http_code}' --max-time 30 "$@") || status=000
    if [ "$status" != "$expected" ]; then
        miss "$label: HTTP $status, expected $expected: $(head -c 120 "$check_dir/body" | tr -c '[:print:]' ' ')"
        return 0
    fi
    if [ "$expected" = 401 ] && ! grep -qi '^WWW-Authenticate: Basic realm="Restricted"' "$check_dir/headers"; then
        miss "$label: 401 without the Restricted Basic challenge"
        return 0
    fi
    if [ "$pattern" != - ] && ! grep -qF -- "$pattern" "$check_dir/body" "$check_dir/headers"; then
        miss "$label: HTTP $status without '$pattern': $(head -c 120 "$check_dir/body" | tr -c '[:print:]' ' ')"
        return 0
    fi
    echo "  ok   $label: HTTP $status"
}

xmlrpc_call='<?xml version="1.0"?><methodCall><methodName>system.client_version</methodName><params/></methodCall>'

# make_torrent <file> <name>: a minimal single-file torrent.
make_torrent() {
    php7.2 -r '
        $info = "d6:lengthi5e4:name" . strlen($argv[2]) . ":" . $argv[2]
            . "12:piece lengthi16384e6:pieces20:" . str_repeat("A", 20) . "e";
        file_put_contents($argv[1], "d8:announce22:http://tracker.invalid4:info" . $info . "e");
    ' "$1" "$2"
}

# endpoint_requests <tag> <expected status> [curl arguments...]
# Requests each endpoint with the given extra curl arguments (credentials).
endpoint_requests() {
    tag=$1 expected=$2
    shift 2
    request "$tag GET /" "$expected" - "$@" "$base/"
    request "$tag GET /pid.php" "$expected" - "$@" "$base/pid.php"
    request "$tag POST /pid.php" "$expected" - "$@" -d a=b "$base/pid.php"
    request "$tag GET /php/setsettings.php" "$expected" - "$@" "$base/php/setsettings.php"
    request "$tag POST /php/setsettings.php" "$expected" - "$@" \
        --data-urlencode "v={\"nginx-auth\":\"$tag\"}" "$base/php/setsettings.php"
    request "$tag GET /php/addtorrent.php" "$expected" - "$@" "$base/php/addtorrent.php"
    request "$tag POST /php/addtorrent.php" "$expected" - "$@" \
        -F "torrent_file=@$check_dir/rejected.torrent" -F torrents_start_stopped=1 \
        "$base/php/addtorrent.php"
    request "$tag GET /plugins/httprpc/action.php" "$expected" - "$@" "$base/plugins/httprpc/action.php"
    request "$tag POST /plugins/httprpc/action.php" "$expected" - "$@" -d mode=list \
        "$base/plugins/httprpc/action.php"
    request "$tag GET /plugins/rpc/rpc.php" "$expected" - "$@" "$base/plugins/rpc/rpc.php"
    request "$tag POST /plugins/rpc/rpc.php" "$expected" - "$@" -H 'Content-Type: text/xml' \
        --data-binary "$xmlrpc_call" "$base/plugins/rpc/rpc.php"
    request "$tag GET /RPC2" "$expected" - "$@" "$base/RPC2"
    request "$tag POST /RPC2" "$expected" - "$@" -H 'Content-Type: text/xml' \
        --data-binary "$xmlrpc_call" "$base/RPC2"
}

echo "== Start the image with a test login"
mkdir -p "$check_dir/bin"
cat > "$check_dir/bin/curl" <<'EOF'
#!/bin/sh
# Answers start.sh's install callback, which cannot reach the API offline.
echo 'HTTP/1.1 200 OK'
EOF
chmod 0755 "$check_dir/bin/curl"
env PATH="$check_dir/bin:$PATH" RUTORRENT_USER="$user" RUTORRENT_PASSWORD="$password" \
    LISTENING_PORT=51413 DHT_PORT=51414 EXTERNAL_DOMAIN=http://127.0.0.1 INSTANCE_ID=0 \
    /scripts/start.sh >"$check_dir/start.log" 2>&1 &

attempt=0
until [ "$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$base/")" = 401 ]; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 120 ] || fail "nginx did not answer with 401 on / within 120s"
    sleep 1
done
printf '%s' '<?php echo "pid=", getmypid(), "\n";' > "$html/pid.php"
chmod 0644 "$html/pid.php"
attempt=0
until [ "$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' --max-time 5 -u "$user:$password" "$base/pid.php")" = 200 ] \
    && [ "$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' --max-time 5 -u "$user:$password" \
        -H 'Content-Type: text/xml' --data-binary "$xmlrpc_call" "$base/RPC2")" = 200 ]; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 120 ] || fail "php-fpm or rTorrent did not answer within 120s"
    sleep 1
done
echo "nginx, php-fpm and rTorrent are up"

make_torrent "$check_dir/rejected.torrent" nginx-auth-rejected.txt
make_torrent "$check_dir/accepted.torrent" nginx-auth-accepted.txt
settings=/torrents/config/rutorrent/users/$user/settings/uisettings.json
cp "$settings" "$check_dir/settings.before"

echo "== Without credentials"
endpoint_requests unauthenticated 401
echo "== With a wrong password"
endpoint_requests wrong-password 401 -u "$user:wrong-$password"

echo "== Nothing was changed without the login"
if ! cmp -s "$settings" "$check_dir/settings.before"; then
    miss "uisettings.json changed: $(head -c 120 "$settings")"
elif [ -e /torrents/config/rutorrent/settings/uisettings.json ]; then
    miss "settings were saved for an anonymous user"
else
    echo "  ok   settings unchanged"
fi
request "torrent list" 200 - -u "$user:$password" -d mode=list "$base/plugins/httprpc/action.php"
if grep -qF nginx-auth-rejected.txt "$check_dir/body"; then
    miss "a torrent was added without the login"
else
    echo "  ok   no torrent was added"
fi

echo "== With the test login"
request "GET /" 200 js/webui.js -u "$user:$password" "$base/"
request "GET /pid.php" 200 pid= -u "$user:$password" "$base/pid.php"
request "POST /pid.php" 200 pid= -u "$user:$password" -d a=b "$base/pid.php"
marker=nginx-auth-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
request "POST /php/setsettings.php" 200 - -u "$user:$password" \
    --data-urlencode "v={\"nginx-auth\":\"$marker\"}" "$base/php/setsettings.php"
if grep -qF "$marker" "$settings"; then
    echo "  ok   settings saved for $user"
else
    miss "settings were not saved: $(head -c 120 "$settings")"
fi
request "GET /php/getsettings.php" 200 "$marker" -u "$user:$password" "$base/php/getsettings.php"
request "POST /php/addtorrent.php" 302 'result[]=Success' -u "$user:$password" \
    -F "torrent_file=@$check_dir/accepted.torrent" -F torrents_start_stopped=1 \
    "$base/php/addtorrent.php"
request "POST /plugins/httprpc/action.php" 200 nginx-auth-accepted.txt -u "$user:$password" \
    -d mode=list "$base/plugins/httprpc/action.php"
request "POST /plugins/rpc/rpc.php" 200 '<methodResponse>' -u "$user:$password" \
    -H 'Content-Type: text/xml' --data-binary "$xmlrpc_call" "$base/plugins/rpc/rpc.php"
request "POST /RPC2" 200 '<methodResponse>' -u "$user:$password" \
    -H 'Content-Type: text/xml' --data-binary "$xmlrpc_call" "$base/RPC2"

echo "== Every PHP file in the web root without credentials"
swept=0 open=
for script in $(cd "$html" && find . -name '*.php' ! -path ./no-auth/share.php | sed 's#^\.##' | sort); do
    swept=$((swept + 1))
    status=$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$base$script") || status=000
    [ "$status" = 401 ] || open="$open $script($status)"
done
if [ -n "$open" ]; then
    miss "$(echo "$open" | wc -w) of $swept PHP files answered without credentials:$(echo "$open" | tr ' ' '\n' | head -n 15 | tr '\n' ' ')"
else
    echo "  ok   all $swept PHP files returned 401"
fi

echo "== Public fileshare links stay open"
request "GET /no-auth/share.php" 200 'Invalid link' "$base/no-auth/share.php"
request "GET /no-auth/share.php?uh=...&s=..." 200 'No such file or it expired' \
    "$base/no-auth/share.php?uh=$(printf '%s' "$user" | base64)&s=missing"

if [ "$failures" -ne 0 ]; then
    echo "FAIL: $failures nginx authentication expectation(s) not met" >&2
    exit 1
fi
echo "nginx requires the login for every PHP endpoint"
