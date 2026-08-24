#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 STAGED_INSTALL_ROOT" >&2
    exit 2
fi

STAGE_ROOT=$(cd "$1" && pwd)
BINARY="$STAGE_ROOT/usr/bin/hlquery"
CONFIG_SOURCE="$STAGE_ROOT/etc/hlquery"
CORE_MODULE="$STAGE_ROOT/usr/lib/hlquery/modules/core_timers.so"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hlquery-daemon-test.XXXXXX")
DAEMON_PID=""

cleanup() {
    if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill -TERM "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT HUP INT TERM

for required_path in "$BINARY" "$CONFIG_SOURCE/hlquery.conf" "$CONFIG_SOURCE/modules.conf" "$CORE_MODULE"; do
    if [ ! -e "$required_path" ]; then
        echo "Missing staged package file: $required_path" >&2
        exit 1
    fi
done

mkdir -p "$TEST_DIR/conf" "$TEST_DIR/log" "$TEST_DIR/data"
cp "$CONFIG_SOURCE"/*.conf "$TEST_DIR/conf/"

PORT=$(perl -MIO::Socket::INET -e '$s=IO::Socket::INET->new(LocalAddr=>"127.0.0.1",LocalPort=>0,Listen=>1,Proto=>"tcp",ReuseAddr=>1) or die $!; print $s->sockport')

sed -i "s|port=\"9200\" type=\"http\"|port=\"$PORT\" type=\"http\"|" "$TEST_DIR/conf/hlquery.conf"
sed -i "s|/var/log/hlquery/|$TEST_DIR/log/|g" "$TEST_DIR/conf/hlquery.conf"
sed -i "s|    # data_dir=\"/var/lib/hlquery/storage\"|    data_dir=\"$TEST_DIR/data\"|" "$TEST_DIR/conf/hlquery.conf"
sed -i "1i<module name=\"core_timers\" path=\"$CORE_MODULE\">" "$TEST_DIR/conf/modules.conf"

"$BINARY" --nofork --nopid --skip-auth --config "$TEST_DIR/conf/hlquery.conf" \
    >"$TEST_DIR/daemon.out" 2>&1 &
DAEMON_PID=$!

request_health() {
    HLQUERY_SMOKE_PORT="$PORT" perl -MIO::Socket::INET -e '
        $socket = IO::Socket::INET->new(
            PeerAddr => "127.0.0.1",
            PeerPort => $ENV{HLQUERY_SMOKE_PORT},
            Proto => "tcp",
            Timeout => 1
        ) or exit 1;
        print $socket "GET /health HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n";
        print while <$socket>;
    '
}

RESPONSE=""
for _attempt in $(seq 1 50); do
    if RESPONSE=$(request_health 2>/dev/null) && printf '%s' "$RESPONSE" | grep -q '^HTTP/[^ ]* 200 '; then
        break
    fi
    RESPONSE=""
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
        break
    fi
    sleep 0.2
done

if [ -z "$RESPONSE" ] || ! printf '%s' "$RESPONSE" | grep -q '"status":"ok"'; then
    echo "Packaged daemon did not become healthy." >&2
    sed -n '1,200p' "$TEST_DIR/daemon.out" >&2
    exit 1
fi

kill -TERM "$DAEMON_PID"
wait "$DAEMON_PID"
DAEMON_PID=""

echo "Packaged daemon smoke test passed on port $PORT."
