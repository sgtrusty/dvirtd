#!/usr/bin/env bash

function get_next_available_display() {
    local max_display=0
    for display in $(cd /tmp/.X11-unix && for x in X*; do echo ":${x#X}"; done); do
        display_number="${display#:}"
        if [ "$display_number" -gt "$max_display" ]; then
            max_display="$display_number"
        fi
    done
    next_display=$((max_display + 1))
    echo ":$next_display"
}

next_display=$(get_next_available_display)
echo $next_display
