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
Type "tmux -f /dev/null new -s leash \; set status off" Enter
Sleep 1s
Type "export PS1='leash$ ' ANTHROPIC_API_KEY=$(security find-generic-password -s leash-anthropic -w) && clear" Enter
Type "./leash -c spike/policy.json serve" Enter
Sleep 2s
Ctrl+B
Type "%"
Sleep 500ms
Type "export PS1='host$ ' && clear && ./spike/vm.sh up 2>&1 | tail -1 && clear" Enter
Wait+Screen@240s /host\$ $/
Show

# ---- 1. the VM holds capabilities, not keys
Type "./spike/vm.sh ssh" Enter
Wait+Screen@30s /dev@agent-vm/
Type "env | grep -E '^(ANTHROPIC|HTTPS_PROXY)' | sed -E 's/(lsh_.{6})[^@]*/\1.../'" Enter
Sleep 4s

# ---- 2. real work, on a key it never sees
Type "claude -p 'Reply with exactly: LEASH_OK'" Enter
Wait+Screen@90s /LEASH_OK/
Sleep 2s

# ---- 3. root tries every way out
Type "clear && ~/leash/attack.sh" Enter
Wait+Screen@180s /all held|FAILED/
Sleep 5s

# ---- 4. the spend cap trips, and the agent can't raise it
Type "clear && ~/leash/cap.sh" Enter
Wait+Screen@300s /REFUSED|never tripped/
Sleep 4s
Type "exit" Enter
Sleep 1s

# ---- 5. who did what, and what it cost
Type "clear && ./leash -c spike/policy.json report" Enter
Sleep 6s

# ---- 6. stop the gateway: access is gone, nothing to scrub
Ctrl+B
Type "o"
Ctrl+C
Sleep 1s
Ctrl+B
Type "o"
Type "clear && ./spike/vm.sh ssh claude -p 'still there?' 2>&1 | tail -2" Enter
Sleep 20s

Hide
Type "./spike/vm.sh down; tmux kill-session -t leash" Enter
Sleep 3s
