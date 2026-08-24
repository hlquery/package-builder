#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INIT_SCRIPT=${1:-$SCRIPT_DIR/hlquery.init}
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hlquery-init-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

CALL_LOG="$TEST_DIR/calls.log"
FAKE_WRAPPER="$TEST_DIR/hlquery-wrapper"
FAKE_SYSTEMCTL="$TEST_DIR/systemctl"

cat > "$FAKE_WRAPPER" <<EOF
#!/bin/sh
printf 'wrapper:%s\n' "\$*" >> "$CALL_LOG"
EOF

cat > "$FAKE_SYSTEMCTL" <<EOF
#!/bin/sh
printf 'systemctl:%s\n' "\$*" >> "$CALL_LOG"
EOF

chmod 0755 "$FAKE_WRAPPER" "$FAKE_SYSTEMCTL"

run_sysv() {
    HLQUERY_INIT_MODE=sysv \
    HLQUERY_WRAPPER="$FAKE_WRAPPER" \
    HLQUERY_RUNTIME_DIR="$TEST_DIR/run" \
    HLQUERY_STATE_DIR="$TEST_DIR/state" \
    HLQUERY_LOG_DIR="$TEST_DIR/log" \
        "$INIT_SCRIPT" "$1"
}

run_sysv start
run_sysv status
run_sysv restart
run_sysv stop

for action in start status restart stop; do
    grep -Fx "wrapper:$action" "$CALL_LOG" >/dev/null
done

: > "$CALL_LOG"
for action in start status restart stop; do
    HLQUERY_INIT_MODE=systemd \
    HLQUERY_SYSTEMCTL="$FAKE_SYSTEMCTL" \
        "$INIT_SCRIPT" "$action"
    grep -Fx "systemctl:$action hlquery.service" "$CALL_LOG" >/dev/null
done

echo "Service init smoke tests passed."
