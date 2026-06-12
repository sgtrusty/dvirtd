# ── orchestration: compose file resolution + build/up/rm ──────────────────

source "$IMPORT_DIR/lib/includes/logging.sh"
source "$IMPORT_DIR/lib/includes/versions.sh"

orc_resolve_version() {
    local image="${1:-builder}" ini="${2:-$VERSION_INI}"
    sed -n "/^\[$image\]/,/^\[/p" "$ini" 2>/dev/null |
        grep '^version' | sed 's/.*=\s*//'
}

orc_resolve_registry() {
    local ini="${1:-$VERSION_INI}"
    sed -n '/^\[meta\]/,/^\[/p' "$ini" 2>/dev/null |
        grep '^registry' | sed 's/.*=\s*//'
}

# Echoes the compose file path; generates from template if no dedicated YML.
orc_compose_file() {
    local image="$1"
    local yml="$RECIPE_DIR/${image}.yml"
    if [[ -f "$yml" ]]; then
        echo "$yml"
        return 0
    fi
    local tmp="$IMPORT_DIR/.tmp/running.yml"
    mkdir -p "$(dirname "$tmp")"
    local ver reg
    ver="$(orc_resolve_version "$image" || echo 0.0.1)"
    reg="$(orc_resolve_registry || echo dvirtd)"
    IMAGE="$image" VERSION="$ver" REGISTRY="$reg" RECIPE_DIR="$RECIPE_DIR" envsubst <"$RECIPE_DIR/template.yml" >"$tmp"
    echo "$tmp"
}

orc_build() {
    local image="$1" compose_file params=""
    compose_file="$(orc_compose_file "$image")"
    MSG_INFO "Building image ${image}"
    MSG "Docker build"
    [[ "${DEBUG:-false}" != "false" ]] && params="--progress=plain"
    DOCKER_BUILDKIT=1 docker-compose -f "$compose_file" build $params &&
        MSG_OK "Docker build" ||
        (MSG_NOK "Docker build" && exit 1)
}

orc_up() {
    local image="$1" compose_file detached="${2:-false}" pipein="${3:-}"
    compose_file="$(orc_compose_file "$image")"
    local env_vars
    env_vars=$(env_assemble)
    MSG "Running docker-compose"
    if [[ "$detached" != "false" ]]; then
        eval "$env_vars docker-compose -f \"$compose_file\" up --force-recreate -V -d devel-$image"
    elif [[ -n "$pipein" ]]; then
        eval "$env_vars docker-compose -f \"$compose_file\" run -T -i --rm ${XEPHYR_MOUNT:-} devel-$image \"arch-entry\" < \"$pipein\""
    else
        eval "$env_vars docker-compose -f \"$compose_file\" run --rm ${XEPHYR_MOUNT:-} devel-$image \"arch-entry\""
    fi
}

orc_rm() {
    local image="$1" compose_file
    compose_file="$(orc_compose_file "$image")"
    docker-compose -f "$compose_file" down -v "$image"
}
