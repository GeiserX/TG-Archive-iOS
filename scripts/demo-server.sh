#!/usr/bin/env bash
# Runs a synthetic Telegram-Archive viewer on this Mac for the app's tests, fixtures and screenshots.
# Every person, chat and message in it is invented by the server project's own demo generator.
#   scripts/demo-server.sh start     clone and install the server if needed, generate the archive once, serve it
#   scripts/demo-server.sh stop      stop the viewer
#   scripts/demo-server.sh status    exit 0 when the viewer answers, 1 otherwise
#   scripts/demo-server.sh reset     stop, regenerate the archive from scratch (this also renews the share
#                                    link, which expires 14 days after generation), start
# Env:
#   DATA_DIR        archive, viewer.pid and viewer.log (default ./demo-data)
#   SRC_DIR         Telegram-Archive checkout (default ./demo-src, shallow-cloned at TG_ARCHIVE_REF on first use)
#   TG_ARCHIVE_REF  server tag to clone (default v9.3.1; bump deliberately)
#   PORT            listen port on 127.0.0.1 (default 8000)
#   DEMO_USERNAME, DEMO_PASSWORD   the master login (default admin / demo-admin-not-a-secret)
# Needs git and uv (brew install uv), which fetches the Python the server needs. ffmpeg on PATH is optional:
# it adds the voice notes, the round video, the videos and the video sticker.
set -euo pipefail

DATA_DIR=${DATA_DIR:-./demo-data}
SRC_DIR=${SRC_DIR:-./demo-src}
TG_ARCHIVE_REF=${TG_ARCHIVE_REF:-v9.3.1}
PORT=${PORT:-8000}
DEMO_USERNAME=${DEMO_USERNAME:-admin}
DEMO_PASSWORD=${DEMO_PASSWORD:-demo-admin-not-a-secret}
REPO_URL=https://github.com/GeiserX/Telegram-Archive

mkdir -p "$DATA_DIR"
DATA_DIR=$(cd "$DATA_DIR" && pwd)
PID_FILE="$DATA_DIR/viewer.pid"
LOG_FILE="$DATA_DIR/viewer.log"
BASE_URL="http://127.0.0.1:$PORT"

running_pid() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid
    pid=$(cat "$PID_FILE")
    kill -0 "$pid" 2>/dev/null || return 1
    echo "$pid"
}

healthy() {
    curl -fsS --max-time 2 "$BASE_URL/api/health" >/dev/null 2>&1
}

ensure_src() {
    command -v uv >/dev/null || { echo "uv is not on PATH; install it with: brew install uv" >&2; exit 1; }
    if [[ ! -f "$SRC_DIR/scripts/generate_dummy_db.py" ]]; then
        echo "cloning Telegram-Archive $TG_ARCHIVE_REF into $SRC_DIR"
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TG_ARCHIVE_REF" "$REPO_URL" "$SRC_DIR"
    fi
    SRC_DIR=$(cd "$SRC_DIR" && pwd)
    (cd "$SRC_DIR" && uv sync --locked --quiet)
}

# The generator's demo credentials are public constants in its source; read them there so they never drift.
generator_constant() {
    sed -n "s/^$1 = \"\(.*\)\"$/\1/p" "$SRC_DIR/scripts/generate_dummy_db.py"
}

generate() {
    command -v ffmpeg >/dev/null || echo "ffmpeg is not on PATH: voice notes, videos and the video sticker get no file"
    "$SRC_DIR/.venv/bin/python" -I "$SRC_DIR/scripts/generate_dummy_db.py" --data-dir "$DATA_DIR" "$@"
}

start() {
    local pid
    if pid=$(running_pid); then
        echo "already running (pid $pid) at $BASE_URL"
        return 0
    fi
    if healthy; then
        echo "something else already answers on $BASE_URL; pick another PORT" >&2
        exit 1
    fi
    ensure_src
    [[ -f "$DATA_DIR/backups/telegram_backup.db" ]] || generate
    # Detach from this shell (setsid through perl, since macOS has no setsid command) so the viewer
    # outlives an ssh session or a CI step.
    BACKUP_PATH="$DATA_DIR/backups" DB_TYPE=sqlite DB_PATH="$DATA_DIR/backups/telegram_backup.db" \
        VIEWER_USERNAME="$DEMO_USERNAME" VIEWER_PASSWORD="$DEMO_PASSWORD" VIEWER_TIMEZONE=UTC \
        nohup perl -MPOSIX=setsid -e 'setsid; exec @ARGV' \
        "$SRC_DIR/.venv/bin/uvicorn" telegram_archive.web.main:app --host 127.0.0.1 --port "$PORT" \
        </dev/null >>"$LOG_FILE" 2>&1 &
    pid=$!
    echo "$pid" >"$PID_FILE"
    for _ in $(seq 1 60); do
        if healthy; then
            echo "demo server running (pid $pid) at $BASE_URL"
            echo "  master login:  $DEMO_USERNAME / $DEMO_PASSWORD"
            echo "  viewer login:  family / $(generator_constant DEMO_VIEWER_PASSWORD)"
            echo "  share link:    $BASE_URL/#token=$(generator_constant DEMO_SHARE_TOKEN)"
            return 0
        fi
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    echo "the viewer did not answer on $BASE_URL; last lines of $LOG_FILE:" >&2
    tail -n 20 "$LOG_FILE" >&2
    kill "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    exit 1
}

stop() {
    local pid
    if ! pid=$(running_pid); then
        rm -f "$PID_FILE"
        echo "not running"
        return 0
    fi
    kill "$pid"
    for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid"
    fi
    rm -f "$PID_FILE"
    echo "stopped (pid $pid)"
}

status() {
    local pid
    if pid=$(running_pid) && healthy; then
        echo "running (pid $pid) at $BASE_URL: $(curl -fsS --max-time 2 "$BASE_URL/api/health")"
        return 0
    fi
    echo "not running at $BASE_URL"
    return 1
}

reset() {
    stop
    ensure_src
    generate --force
    start
}

case "${1:-}" in
    start | stop | status | reset) "$1" ;;
    *)
        echo "usage: $0 start|stop|status|reset" >&2
        exit 2
        ;;
esac
