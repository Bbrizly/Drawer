#!/usr/bin/env bash
# End-to-end smoke test for the drawer-mcp server: spawn the binary, drive an
# add/list/toggle over stdio, and assert the drawer file changed. Exits non-zero
# on any failure. Run: scripts/mcp-smoke.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "building drawer-mcp..."
swift build --product drawer-mcp >/dev/null
BIN="$(swift build --target drawer-mcp --show-bin-path)/drawer-mcp"

FILE="$(mktemp -t drawer-mcp-smoke).md"
rm -f "$FILE"
TODAY="$(date +%Y-%m-%d)"
LINE="- [ ] smoke task (25m)"

# A real MCP client keeps stdin open; feed requests with small gaps so the
# server stays alive through the exchange (an instant EOF races the read loop).
drive() {
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}'; sleep 0.4
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'; sleep 0.3
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"add_task\",\"arguments\":{\"title\":\"smoke task\",\"minutes\":25}}}"; sleep 0.5
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_tasks","arguments":{"section":"today"}}}'; sleep 0.4
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"toggle_task\",\"arguments\":{\"id\":\"${TODAY}|0|${LINE}\"}}}"; sleep 0.5
}

OUT="$(drive | "${TIMEOUT:-gtimeout}" 8 "$BIN" --file "$FILE" 2>/dev/null || true)"

fail() { echo "SMOKE FAIL: $1"; echo "--- file ---"; cat "$FILE" 2>/dev/null || echo "(no file)"; exit 1; }

grep -qF "smoke task" <<<"$OUT" || fail "list_tasks did not return the added task"
[ -f "$FILE" ] || fail "server never created the drawer file"
grep -q "^## ${TODAY}$" "$FILE" || fail "today section not created"
grep -qF -- "- [x] smoke task (25m)" "$FILE" || fail "task was not added and toggled done"

echo "SMOKE PASS: add + list + toggle drove the file to a checked task"
rm -f "$FILE"
