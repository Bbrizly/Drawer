#!/usr/bin/env bash
# End-to-end smoke test for drawer-mcp: spawn the binary and drive a real MCP
# stdio exchange (initialize -> add_task -> list_tasks -> toggle_task), then
# assert the drawer file changed. Uses the id returned by list_tasks (not a
# hardcoded format) and fails on any bad response, missing tool, or crash.
# Requires python3. Run: scripts/mcp-smoke.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "building drawer-mcp..."
swift build --product drawer-mcp >/dev/null
BIN="$(swift build --target drawer-mcp --show-bin-path)/drawer-mcp"
TMP="$(mktemp -t drawer-mcp-smoke)"
FILE="$TMP.md"
# Clean up both temp names on every exit path, not just success.
trap 'rm -f "$TMP" "$FILE"' EXIT

BIN="$BIN" FILE="$FILE" python3 - <<'PY'
import json, os, signal, subprocess, sys

# A hung server must fail the run, not hang CI: the whole exchange gets one
# hard deadline.
def on_timeout(signum, frame):
    print("SMOKE FAIL: timed out waiting for the server")
    proc.kill(); sys.exit(1)
signal.signal(signal.SIGALRM, on_timeout)
signal.alarm(30)

bin_path, file_path = os.environ["BIN"], os.environ["FILE"]
proc = subprocess.Popen(
    [bin_path, "--file", file_path],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
)

def fail(msg):
    print(f"SMOKE FAIL: {msg}")
    try: print(open(file_path).read())
    except FileNotFoundError: print("(no file)")
    proc.kill(); sys.exit(1)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n"); proc.stdin.flush()

def read_result(req_id):
    # Read newline-delimited JSON-RPC until the matching response arrives.
    for line in proc.stdout:
        line = line.strip()
        if not line: continue
        msg = json.loads(line)
        if msg.get("id") == req_id:
            if "error" in msg: fail(f"request {req_id} errored: {msg['error']}")
            return msg["result"]
    fail(f"no response for request {req_id} (server exited early)")

def call(req_id, name, arguments):
    send({"jsonrpc": "2.0", "id": req_id, "method": "tools/call",
          "params": {"name": name, "arguments": arguments}})
    result = read_result(req_id)
    if result.get("isError"):
        fail(f"{name} returned a tool error: {result['content'][0]['text']}")
    return json.loads(result["content"][0]["text"])

send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
      "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                 "clientInfo": {"name": "smoke", "version": "1"}}})
init = read_result(1)
if init.get("serverInfo", {}).get("name") != "drawer":
    fail(f"unexpected serverInfo: {init.get('serverInfo')}")
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

added = call(2, "add_task", {"title": "smoke task", "minutes": 25})
if added.get("title") != "smoke task":
    fail(f"add_task did not echo the task: {added}")

tasks = call(3, "list_tasks", {"section": "today"})
match = next((t for t in tasks if t["title"] == "smoke task"), None)
if not match:
    fail(f"list_tasks did not return the added task: {tasks}")

toggled = call(4, "toggle_task", {"id": match["id"]})
if not toggled.get("done"):
    fail(f"toggle_task did not report done: {toggled}")

proc.stdin.close(); proc.wait(timeout=5)

content = open(file_path).read()
if "- [x] smoke task (25m)" not in content:
    fail(f"file does not show the checked task:\n{content}")

print("SMOKE PASS: initialize + add + list + toggle drove the file to a checked task")
PY
