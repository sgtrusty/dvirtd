#!/usr/bin/env bash

DUMMY_SOCKET=/tmp/pulseaudio.socket

if [ ! -e "$DUMMY_SOCKET" ]; then
    if pactl info &>/dev/null; then
        PULSE_MODULE_ID=$(pactl load-module module-native-protocol-unix socket="$DUMMY_SOCKET" 2>/dev/null) || true
        export PULSE_MODULE_ID
    fi
fi

dummy_driver_cleanup() {
    if [[ -n "${PULSE_MODULE_ID:-}" ]]; then
        pactl unload-module "$PULSE_MODULE_ID" 2>/dev/null || true
    fi
}
CLEANUP_HOOKS+=("dummy_driver_cleanup")
