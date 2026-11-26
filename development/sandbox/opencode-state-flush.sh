#!/usr/bin/env bash
# Checkpoint OpenCode's SQLite WAL and flush the state volume before the VM is
# destroyed. Runs inside the sandbox as the agent user (see Makefile sbx-flush).
#
# OpenCode opens SQLite with journal_mode=WAL and synchronous=NORMAL, so commits
# are not fsynced until a checkpoint or a clean close. `sbx rm` destroys the
# microVM, so the guest must flush the volume before removal or the newest
# sessions are lost.
set -euo pipefail

state_dir=${OPENCODE_STATE_DIR:-/home/agent/.local/share/opencode}
db="$state_dir/opencode.db"

if [ ! -f "$db" ]; then
  echo "opencode-state-flush: no $db; nothing to checkpoint"
else
  # PASSIVE never blocks writers; if OpenCode is mid-transaction the remaining
  # WAL frames stay durable via the sync below and SQLite replays them on boot.
  python3 - "$db" <<'PY'
import sqlite3
import sys

con = sqlite3.connect(sys.argv[1], timeout=5.0)
try:
    busy, log_frames, checkpointed = con.execute(
        "PRAGMA wal_checkpoint(PASSIVE)"
    ).fetchone()
finally:
    con.close()

print(
    "opencode-state-flush: wal checkpoint "
    f"busy={busy} log={log_frames} checkpointed={checkpointed}"
)
if busy:
    print(
        "opencode-state-flush: checkpoint incomplete; remaining WAL frames "
        "are made durable by the sync below",
        file=sys.stderr,
    )
PY
fi

if sync -f "$state_dir"; then
  echo "opencode-state-flush: synced $state_dir"
else
  echo "opencode-state-flush: sync -f failed; falling back to global sync" >&2
  sync
fi
