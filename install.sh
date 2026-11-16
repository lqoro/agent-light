#!/bin/bash
# Build, install to ~/Applications, add LaunchAgent, symlink CLI. Applies codex/gemini hooks only if their config exists.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
./build.sh
mkdir -p ~/Applications
rm -rf ~/Applications/AgentLight.app
cp -R AgentLight.app ~/Applications/

PLIST=~/Library/LaunchAgents/com.agentlight.app.plist
mkdir -p ~/Library/LaunchAgents
cat > "$PLIST" <<EOP
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.agentlight.app</string>
  <key>ProgramArguments</key><array><string>$HOME/Applications/AgentLight.app/Contents/MacOS/AgentLight</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
EOP
launchctl bootout "gui/$(id -u)/com.agentlight.app" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

ln -sf "$ROOT/bin/agentlight" /opt/homebrew/bin/agentlight

# Codex: notify fires on turn completion only -> "done". Skip if config missing or notify already set.
CODEX=~/.codex/config.toml
if [ -f "$CODEX" ]; then
  if grep -q '^notify' "$CODEX"; then echo "codex: notify already set, skipping"
  else
    cp "$CODEX" "$CODEX.bak.$(date +%s)"
    # top-level keys must come before any [table]
    { cat "$ROOT/hooks/codex-config.toml"; echo; cat "$CODEX"; } > "$CODEX.new" && mv "$CODEX.new" "$CODEX"
    echo "codex: notify added"
  fi
fi

# Gemini: merge hooks into settings.json (python3 handles JSON), only if the file exists.
GEM=~/.gemini/settings.json
if [ -f "$GEM" ]; then
  cp "$GEM" "$GEM.bak.$(date +%s)"
  /usr/bin/python3 - "$GEM" "$ROOT/hooks/gemini-settings.json" <<'EOP'
import json, sys
cur, add = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
cur.setdefault("hooks", {}).update(add["hooks"])
json.dump(cur, open(sys.argv[1], "w"), indent=2)
EOP
  echo "gemini: hooks merged"
fi

echo "Installed. Claude Code hooks are NOT applied automatically: merge hooks/claude-settings.json into ~/.claude/settings.json."
