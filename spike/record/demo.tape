# demo.tape -- a reproducible terminal recording of the spike.
#
#   brew install vhs tmux
#   ./spike/vm.sh provision           # once, off camera (takes a few minutes)
#   vhs spike/record/demo.tape        # from the repo root -> spike/record/leash-demo.mp4
#
# Needs VHS 0.8+ for `Wait`. The Anthropic key is read from the macOS keychain
# while the recording is hidden; it never appears on screen or in the VM.
# Store it once with:
#   security add-generic-password -a "$USER" -s leash-anthropic -w
# Use a dedicated key with a low spend limit set in the Anthropic console.

Output spike/record/leash-demo.mp4

Require tmux
Require qemu-img

Set Shell "bash"
Set FontSize 17
Set Width 1720
Set Height 960
Set Padding 24
Set TypingSpeed 35ms
Set WindowBar Colorful

# ---- setup, off camera: gateway in the left pane, VM booted in the right
Hide
Type "export PS1='host$ ' && clear" Enter
# an aborted recording leaves its VM, tmux session and gateway behind; the
# duplicate session then keeps every later keystroke out of tmux
Type "./spike/vm.sh down >/dev/null 2>&1; tmux -L leash-record kill-server 2>/dev/null; clear" Enter
Sleep 2s
Type "tmux -L leash-record -f /dev/null new -s leash \; set status off" Enter
Sleep 1s
Type "export PS1='leash$ ' ANTHROPIC_API_KEY=$(security find-generic-password -s leash-anthropic -w) && clear" Enter
Type "./leash -c spike/policy.json --session ${LEASH_SESSION:-demo} init && ./leash -c spike/policy.json --session ${LEASH_SESSION:-demo} serve" Enter
Sleep 2s
Ctrl+B
Type "%"
Sleep 500ms
Type "export PS1='host$ ' && clear && ./spike/vm.sh up 2>&1 | tail -1" Enter
# Go regexp: without (?m), $ is the end of the whole screen, never a line.
Wait+Screen@240s /\[vm\] ready: session/
Type "./leash -c spike/policy.json --session ${LEASH_SESSION:-demo} preflight --require-route anthropic --fresh" Enter
Wait+Screen@15s /preflight passed/
Type "./spike/vm.sh ssh command -v claude" Enter
Wait+Screen@15s /\/.local\/bin\/claude/
Type "clear" Enter
Sleep 500ms
Show

# ---- 0. one way out, enforced by QEMU on the host
Type "./spike/vm.sh status" Enter
Sleep 5s
Type "clear" Enter

# ---- 1. the VM holds capabilities, not keys
Type "./spike/vm.sh ssh" Enter
Wait+Screen@30s /dev@agent-vm/
Type "env | grep -E '^(ANTHROPIC|HTTPS_PROXY)' | sed -E 's/(lsh_.{6})[^@]*/\1.../'" Enter
Sleep 4s

# ---- 2. real work, on a key it never sees
Type "CLAUDE_CODE_MAX_RETRIES=0 claude --model haiku -p 'Reply with exactly: LEASH_OK'" Enter
# Not just /LEASH_OK/: the typed prompt contains it. Output sits after the pane border.
Wait+Screen@90s /│LEASH_OK/
Sleep 2s

# ---- 3. root tries every way out
Type "exit" Enter
Sleep 1s
Type "clear && ./spike/vm.sh verify" Enter
Wait+Screen@180s /all held: tested bypasses blocked/
Sleep 5s

# ---- 4. the spend cap trips, and the agent can't raise it
Type "clear && ./spike/vm.sh ssh leash/cap.sh" Enter
Wait+Screen@300s /REFUSED/
Sleep 4s
# ---- 5. who did what, and what it cost
Type "clear && ./leash -c spike/policy.json --session ${LEASH_SESSION:-demo} report" Enter
Sleep 6s

# ---- 6. stop the gateway: access is gone, nothing to scrub
Ctrl+B
Type "o"
Ctrl+C
Sleep 1s
Ctrl+B
Type "o"
# Claude Code otherwise retries with backoff for ~3 minutes before giving up.
Type "clear && ./spike/vm.sh ssh CLAUDE_CODE_MAX_RETRIES=0 claude -p 'still there?' 2>&1 | tail -2" Enter
Wait+Screen@60s /API Error/
Sleep 5s

Hide
Type "./spike/vm.sh down; tmux -L leash-record kill-session -t leash" Enter
Sleep 3s
