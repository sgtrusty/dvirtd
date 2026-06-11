#!/bin/bash

# Configuration: Path to the temp file
# Using a static path so the 'Get' function can find it across different sessions
EXPLORER_TEMP='/tmp/explorer_find_result'

# --- 1. Core Logic ---
# This is the function that actually runs the UI
function explorer-find() {
    local tmp="$EXPLORER_TEMP"
    local explorer=""

    # Detection Logic
    if command -v yazi >/dev/null 2>&1; then
        explorer="yazi"
    elif command -v ranger >/dev/null 2>&1; then
        explorer="ranger"
    else
        echo "Error: No explorer found." >&2
        return 1
    fi

    # Run the explorer and save the path to the temp file
    if [ "$explorer" = "yazi" ]; then
        yazi --cwd-file="$tmp" "$@"
    else
        ranger --choosedir="$tmp" "$@"
    fi

    # Optional: If you want the NEW window to stay open in that dir:
    if [ -f "$tmp" ]; then
        local cwd=$(cat "$tmp")
        [ -n "$cwd" ] && cd "$cwd"
    fi
}

# --- 2. The Getter ---
# Use this to retrieve the path in your original shell
function explorer-find-get() {
    if [ -f "$EXPLORER_TEMP" ]; then
        cat "$EXPLORER_TEMP"
        rm -f "$EXPLORER_TEMP"
    else
        echo ""
    fi
}

# --- 3. The Window Maker ---
# Opens the explorer in a new terminal window
function explorer-find-mkwin() {
    # Ensure the temp file is clean before starting
    rm -f "$EXPLORER_TEMP"

    # The command to run in the new window
    # Note: We source the file so the new shell knows the function
    local cmd="source \"$IMPORT_DIR/lib/includes/explorer_find.sh\" && explorer-find"

    if command -v alacritty >/dev/null 2>&1; then
        alacritty -e $SHELL -c "$cmd"
    elif command -v kitty >/dev/null 2>&1; then
        kitty sh -c "$cmd"
    elif command -v wezterm >/dev/null 2>&1; then
        wezterm start -- $SHELL -c "$cmd"
    else
        # Fallback for generic xterm-based emulators
        xterm -e "$SHELL -c '$cmd'"
    fi
}
