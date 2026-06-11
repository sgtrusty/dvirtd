#!/usr/bin/env bash

IMPORT_DIR=$(realpath "$(dirname "$0")"/..)
source "$IMPORT_DIR/lib/includes/logging.sh"
source "$IMPORT_DIR/lib/display.sh"
source "$IMPORT_DIR/lib/env.sh"
source "$IMPORT_DIR/lib/orchestrator.sh"

# ── YML x-dvirtd reader ──────────────────────────────────────────────────

xget() {
    local yml="$1" key="$2"
    sed -n '/^x-dvirtd:/,/^[a-z#]/p' "$yml" 2>/dev/null |
        grep -E "^  ${key}:" | sed 's/^  [^:]*:\s*//' | head -1 || true
}

list_images() {
    for f in "$RECIPE_DIR"/*.yml; do
        local base
        base=$(basename "$f" .yml)
        case "$base" in template | tailscale-subnet) continue ;; esac
        echo "$base"
    done
}

show_help() {
    MSG "Usage: dvirtd.sh <command> [args]"
    echo
    MSG "Commands:"
    echo "  run <image> [cmdopt]   Run an interactive container"
    echo "  list                   List available images"
    echo "  help                   Show this help"
    echo
    MSG "Run options (cmdopt, comma-separated, from x-dvirtd.cmdopt):"
    echo "  choosedir     Interactive directory selection via cache_selection"
    echo "  usedir        Mount \$PWD as shared volume (requires dirname confirmation)"
    echo "  samedir       Alias for usedir"
    echo "  useforce      Skip confirmation with usedir"
    echo "  usetemp       Mount a temp directory as shared volume"
    echo "  useview       Launch in nested Xephyr window (default: no display)"
    echo "  smallview     Launch in 1024x768 Xephyr (default: 1920x1280)"
    echo "  usepersist    Persist container filesystem across runs"
    echo "  usemake       Override entry-app to 'make'"
    echo
    MSG "Overrides:"
    echo "  CMDOPT arg            Override x-dvirtd.cmdopt"
    echo "  ENTRY_VARS=...        Extra env vars for the container"
    echo "  DVIRTD_RECIPE_DIR=... Path to recipe directory (default: /opt/dvirtd/recipe)"
}

# ── command dispatch ─────────────────────────────────────────────────────

CMD="${1:-}"
shift 2>/dev/null || true

case "$CMD" in
"" | -h | --help | help)
    show_help
    exit 0
    ;;
list)
    list_images
    exit 0
    ;;
run) ;;
*)
    MSG_NOK "Unknown command: ${CMD}"
    show_help
    exit 1
    ;;
esac

# ── image selection (run) ─────────────────────────────────────────────────

IMAGE="${1:-}"

if [[ -z "$IMAGE" ]]; then
    apps=$(list_images)
    IMAGE=$(echo "$apps" | rofi -dmenu -p "Select image > ") || exit 1
    [[ -z "$IMAGE" ]] && exit 1
fi

YML="$RECIPE_DIR/${IMAGE}.yml"
if [[ ! -f "$YML" ]]; then
    MSG_NOK "No recipe found for ${YELLOW}${IMAGE}${RESET}"
    exit 1
fi

# ── read x-dvirtd config ─────────────────────────────────────────────────

CMDOPT=$(xget "$YML" cmdopt)
ENTRY_APP=$(xget "$YML" entry-app)
SHARED_VOLUME=$(xget "$YML" shared-volume)
USE_PREF=$(xget "$YML" use-pref-volume)

SHARED_VOLUME="${SHARED_VOLUME//\$\{IMPORT_DIR\}/$IMPORT_DIR}"
SHARED_VOLUME="${SHARED_VOLUME//\$IMPORT_DIR/$IMPORT_DIR}"

# ── build if image missing locally (prerequisite) ────────────────────────

source "$IMPORT_DIR/lib/includes/versions.sh"
local_repo=$(version_image_full "$IMAGE" 2>/dev/null || echo "")
if [[ -n "$local_repo" ]] && ! docker images --filter "reference=${local_repo}" --format '{{.Repository}}' | grep -q .; then
    MSG_INFO "Image not found locally — building via dvirtmg"
    "$IMPORT_DIR/bin/dvirtmg.sh" build "$IMAGE" patch auto
fi

# ── prescript (after successful build) ───────────────────────────────────

PRESCRIPT=$(xget "$YML" prescript)
if [[ -n "$PRESCRIPT" ]]; then
    p="$IMPORT_DIR/lib/prescript/${PRESCRIPT}.sh"
    if [[ -f "$p" ]]; then
        MSG_INFO "Running prescript: ${PRESCRIPT}"
        source "$p"
    else
        MSG_NOK "Prescript not found: ${p}"
    fi
fi

# Source init scripts (comma-separated list)
INIT_SCRIPTS=$(xget "$YML" init-scripts)
CLEANUP_HOOKS=()
if [[ -n "$INIT_SCRIPTS" ]]; then
    IFS=',' read -ra scripts <<<"$INIT_SCRIPTS"
    for script in "${scripts[@]}"; do
        script=$(echo "$script" | xargs)
        spath="$IMPORT_DIR/lib/init/${script}.sh"
        if [[ -f "$spath" ]]; then
            MSG_INFO "Running init: ${script}"
            source "$spath"
        else
            MSG_NOK "Init script not found: ${spath}"
        fi
    done
fi

# ── cleanup trap ─────────────────────────────────────────────────────────

trap_cleanup() {
    local hook
    for hook in "${CLEANUP_HOOKS[@]:-}"; do
        type "$hook" &>/dev/null && "$hook"
    done
    if [[ -n "${SAFECODE_TMP:-}" ]]; then
        rm -rf "$SAFECODE_TMP" 2>/dev/null || true
    fi
}
trap trap_cleanup EXIT INT TERM

# ── CMDOPT parsing ───────────────────────────────────────────────────────

CMDOPT="${2:-$CMDOPT}"
SHARED_VOLUME="${SHARED_VOLUME:-${IMPORT_DIR}/.cache/shared}"

if [[ "$CMDOPT" == *"choosedir"* ]]; then
    source "$IMPORT_DIR/lib/includes/cache_selection.sh"
    SHARED_VOLUME=$(cache_selection "$IMPORT_DIR/.tmp/suggestions" "$IMAGE")
elif [[ "$CMDOPT" == *"usedir"* || "$CMDOPT" == *"samedir"* ]]; then
    SHARED_VOLUME=$PWD
    EXPECTED_NAME=$(basename "$SHARED_VOLUME")
    if [[ "$CMDOPT" != *"useforce"* ]]; then
        echo "CRITICAL: You are about to operate on: $SHARED_VOLUME"
        echo "To proceed, manually type the directory name ['$EXPECTED_NAME']:"
        read -r USER_CONFIRMATION
        if [[ "$USER_CONFIRMATION" != "$EXPECTED_NAME" ]]; then
            echo "Verification failed. Expected '$EXPECTED_NAME' but got '$USER_CONFIRMATION'."
            exit 1
        fi
    fi
fi

if [[ -n "$SHARED_VOLUME" && "$USE_PREF" == "true" ]]; then
    SHARED_VOLUME_BASE=$(basename "$SHARED_VOLUME")
    PREF_VOLUME="${IMPORT_DIR}/.tmp/pref/${SHARED_VOLUME_BASE}"
    mkdir -p "$PREF_VOLUME"
fi

if [[ "$CMDOPT" == *"usetemp"* ]]; then
    SAFECODE_TMP=$(mktemp -d)
    MSG_INFO "Using TMP folder '${SAFECODE_TMP}'"
fi

if [[ "$CMDOPT" == *"useview"* ]]; then
    WINMAG=i3
    ENTRY_APP="${ENTRY_APP:-kitty}"
elif [[ "$CMDOPT" == *"smallview"* ]]; then
    XEPHYR_SIZE=1024x768
else
    WINMAG=bash
    APPDISPLAY=:0
    ENTRY_APP="${ENTRY_APP:-bash}"
fi

if [[ "$CMDOPT" == *"usepersist"* ]]; then
    PERSIST=1
else
    PERSIST=0
fi

if [[ "$CMDOPT" == *"usemake"* ]]; then
    ENTRY_APP="make"
fi

# ── launch ───────────────────────────────────────────────────────────────

export SHARED_VOLUME="${SHARED_VOLUME:=}"
export PREF_VOLUME="${PREF_VOLUME:=}"
export SAFECODE_TMP="${SAFECODE_TMP:=}"
export ENTRY_APP="${ENTRY_APP:=kitty}"
export ENTRY_VARS="${ENTRY_VARS:=}"
export ENTRY_DIR="${ENTRY_DIR:=/home/archlinux/shared}"
export PERSIST="${PERSIST:=0}"
export APPDISPLAY="${APPDISPLAY:=}"
export WINMAG="${WINMAG:=i3}"

# ── Xephyr (after all prereqs: init, build, prescript) ───────────────────

if [[ "$CMDOPT" == *"useview"* || "$CMDOPT" == *"smallview"* ]]; then
    APPDISPLAY="${APPDISPLAY:-$(dpy_next_available)}"
    XEPHYR_SIZE="${XEPHYR_SIZE:-1920x1280}"
    XEPHYR_OPTS="${XEPHYR_OPTS:--no-host-grab}"
    APPNAME="${APPNAME:-archdevel-${IMAGE}}"
    dpy_start_xephyr "$APPDISPLAY" "$XEPHYR_SIZE" "$XEPHYR_OPTS" "$APPNAME"
    XEPHYR_MOUNT=$(dpy_xephyr_mount "$APPDISPLAY")
fi

MSG_INFO "Running: ${IMAGE}"
orc_up "$IMAGE"
