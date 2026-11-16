# Agent Light

Status logos in the MacBook notch for coding agents (Claude Code, Codex CLI, Gemini CLI, Muse Code).
On notched displays a black "ear" shape extends the notch left (then right) and holds one logo per agent.
Ring = its most urgent session: amber fast pulse (needs_input) > red (error) > blue slow breathe (working) > green (done, gone after 60s).
Sessions with no update for 30 min are dropped. Count badge when an agent has more than one session.
Without a notch, loose logos sit at the top-right of the menu bar.
Click a logo for a popover (Open brings the terminal app forward, Dismiss deletes the session). Right-click: Clear all done / Quit.

## Use
    ./build.sh      # builds AgentLight.app
    ./install.sh    # build + ~/Applications + LaunchAgent + symlink in /opt/homebrew/bin
    agentlight <agent> <state> [session]   # states: working needs_input done error idle clear
    agentlight status
    agentlight test working                # fake session "test"

State files: `~/.agentlight/state/<agent>__<session>.json`. Hooks read JSON from stdin (Claude, Gemini) or the last argv (Codex notify).

## Hooks
Snippets are in `hooks/`. install.sh applies Codex and Gemini ones only if their config exists (after a backup).
Claude Code is manual: merge `hooks/claude-settings.json` into `~/.claude/settings.json`.
- Codex: notify fires only when a turn completes, so it shows "done" only.
- Gemini: AfterAgent may not fire on text-only replies; the 30 min expiry covers it.
- Muse: only PreToolUse is verified (see TODO in `hooks/muse-hooks.json`).

Custom logos: drop `icons/<agent>.png`. Otherwise the installed app icon is used, else a colored monogram.
