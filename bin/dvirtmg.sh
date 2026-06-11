#!/usr/bin/env bash
# dvirtmg.sh — Docker Version Manager

IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$IMPORT_DIR/lib/includes/logging.sh"
source "$IMPORT_DIR/lib/includes/versions.sh"
source "$IMPORT_DIR/lib/orchestrator.sh"

VERSION_INI="$IMPORT_DIR/version.ini"

semver_inc() {
    local ver="$1" level="${2:-patch}"
    ver="${ver#v}"
    IFS='.' read -r ma mi pa <<<"$ver"
    ma=${ma:-0} mi=${mi:-0} pa=${pa:-0}
    pa="${pa%%[^0-9]*}"
    pa=${pa:-0}
    case "$level" in
    major) printf '%d.0.0\n' $((ma + 1)) ;;
    minor) printf '%d.%d.0\n' "$ma" $((mi + 1)) ;;
    patch) printf '%d.%d.%d\n' "$ma" "$mi" $((pa + 1)) ;;
    *)
        printf '%s\n' "$ver"
        return 1
        ;;
    esac
}

ini_set() {
    local section="$1" key="$2" val="$3" ini="${4:-$VERSION_INI}"
    local tmp
    tmp="$(mktemp "${ini}.XXXXXX")"
    awk -v sec="[$section]" -v k="$key" -v v="$val" '
        BEGIN { found=0; printed=0 }
        $0 == sec { found=1; print; next }
        found && /^\[/ { if (!printed) { print k " = " v; printed=1 } found=0 }
        found && $0 ~ ("^" k "[[:space:]]*=") { print k " = " v; printed=1; next }
        { print }
        END { if (found && !printed) print k " = " v }
    ' "$ini" >"$tmp" && mv "$tmp" "$ini"
}

list_dependents() {
    local section="$1" ini="${2:-$VERSION_INI}"
    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        local dep
        dep="$(version_depends "$s" "$ini" || true)"
        [[ "$dep" == "$section" ]] && printf '%s\n' "$s"
    done < <(version_sections "$ini")
}

bump_section() {
    local section="$1" level="${2:-patch}" ini="${3:-$VERSION_INI}"
    if [[ "$(version_immutable "$section" "$ini")" == "true" ]]; then
        MSG_INFO "${YELLOW}${section}${RESET} is immutable — locked at $(version_current "$section" "$ini")"
        return 0
    fi
    local cur new
    cur="$(version_current "$section" "$ini" || true)"
    [[ -z "${cur:-}" ]] && {
        MSG_NOK "No version for section: $section"
        return 1
    }
    new="$(semver_inc "$cur" "$level")"
    ini_set "$section" version "$new" "$ini"
    MSG_OK "${YELLOW}${section}${RESET}: ${cur} → ${GREEN}${new}${RESET}"
}

get_dockerfile_for() {
    local section="$1"
    local df="$RECIPE_DIR/images/${section}.dockerfile"
    [[ -f "$df" ]] && {
        echo "$df"
        return 0
    }
    local yml="$RECIPE_DIR/${section}.yml"
    if [[ -f "$yml" ]]; then
        grep 'dockerfile:' "$yml" 2>/dev/null | sed 's/.*dockerfile:\s*//' | head -1
    fi
}

xget_yml() {
    local yml="$1" key="$2"
    [[ ! -f "$yml" ]] && return 0
    sed -n '/^x-dvirtd:/,/^[a-z#]/p' "$yml" 2>/dev/null |
        grep -E "^  ${key}:" | sed 's/^  [^:]*:\s*//' | head -1 || true
}

generate_version_ini() {
    local reg="${1:-dvirtd}"
    MSG_INFO "Generating version.ini from recipes"
    local tmp
    tmp="$(mktemp)"
    {
        echo '; Central version manifest for all managed Docker images.'
        echo '; Auto-generated from recipe YML files and dockerfiles.'
        echo
        echo '[meta]'
        echo "registry = $reg"
        echo
    } >"$tmp"

    local yml
    for yml in "$RECIPE_DIR"/*.yml; do
        local base
        base="$(basename "$yml" .yml)"
        case "$base" in
        template | mariadb | tailscale-subnet | wine-unsafe) continue ;;
        esac

        local df_rel df_path parent
        df_rel="$(get_dockerfile_for "$base" || true)"
        if [[ -n "$df_rel" && ! "$df_rel" =~ ^/ ]]; then
            df_path="$RECIPE_DIR/$df_rel"
        elif [[ -n "$df_rel" ]]; then
            df_path="$df_rel"
        else
            df_path=""
        fi

        if [[ -n "$df_path" && -f "$df_path" ]]; then
            parent="$(grep -oP 'FROM\s+\$\{REGISTRY\}\/\K[^:}]+' "$df_path" 2>/dev/null | head -1 || true)"
        fi

        {
            echo "[$base]"
            echo "version = 0.0.0"
            echo "image = $base"
            if [[ -n "$parent" ]]; then
                echo "depends = $parent"
                echo "depends_ver = 0.0.0"
            fi
            if [[ "$base" == "builder" ]]; then
                echo "immutable = true"
            else
                echo "state = pending"
            fi
            echo
        } >>"$tmp"
    done

    # Discover predeps (images referenced in x-dvirtd.predep without their own YML)
    local pd pd_list
    pd_list=$(
        for yml in "$RECIPE_DIR"/*.yml; do
            base=$(basename "$yml" .yml)
            case "$base" in template | mariadb | tailscale-subnet | wine-unsafe) continue ;; esac
            sed -n '/^x-dvirtd:/,/^[a-z#]/p' "$yml" 2>/dev/null |
                grep -E '^  predep:' | sed 's/^  predep:\s*//' | tr ',' '\n'
        done | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u || true
    )

    for pd in $pd_list; do
        grep -q "^\[$pd\]" "$tmp" 2>/dev/null && continue
        local df_path="$RECIPE_DIR/images/${pd}.dockerfile"
        [[ ! -f "$df_path" ]] && continue
        local parent
        parent="$(grep -oP 'FROM\s+\$\{REGISTRY\}\/\K[^:}]+' "$df_path" 2>/dev/null | head -1 || true)"
        {
            echo "[$pd]"
            echo "version = 0.0.0"
            echo "image = $pd"
            echo "depends = $parent"
            echo "depends_ver = 0.0.0"
            echo "state = pending"
            echo
        } >>"$tmp"
    done

    mv "$tmp" "$VERSION_INI"
    MSG_OK "Generated $VERSION_INI"
}

# ── commands ────────────────────────────────────────────────────────────────

cmd_list() {
    local reg
    reg="$(version_registry)"
    docker images --filter "reference=${reg}/*" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null ||
        echo "No ${reg} images found"
}

cmd_current() {
    local section="${1:-}"
    if [[ -z "$section" ]]; then
        version_sections
        return 0
    fi
    local reg img ver
    reg="$(version_registry)"
    img="$(version_image "$section" || true)"
    ver="$(version_current "$section" || true)"
    [[ -z "${img:-}" ]] && {
        MSG_NOK "Unknown section: $section"
        return 1
    }
    printf '%s/%s:%s\n' "$reg" "$img" "${ver:-(unknown)}"
}

cmd_outdated() {
    local flag="${1:-}" reg
    shift 2>/dev/null || true
    local -a targets=("$@")
    reg="$(version_registry)"

    local outdated=() pending_list=()
    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        if ((${#targets[@]} > 0)); then
            local matched=false
            for t in "${targets[@]}"; do
                [[ "$s" == "$t" ]] && { matched=true; break; }
            done
            [[ "$matched" == "true" ]] || continue
        fi
        local st
        st="$(version_state "$s" || true)"
        if [[ "$st" == "outdated" ]]; then
            outdated+=("$s")
        elif [[ "$st" == "pending" ]]; then
            pending_list+=("$s")
        fi
    done < <(version_sections)

    if [[ "$flag" == "--fix" ]]; then
        local all=("${pending_list[@]}" "${outdated[@]}")
        if ((${#all[@]} == 0)); then
            MSG_OK "All images are up to date"
            return 0
        fi
        for s in "${all[@]}"; do
            echo
            MSG_INFO "Rebuilding: ${s}"
            cmd_build "$s" "patch" "auto"
        done
    else
        if ((${#pending_list[@]} == 0 && ${#outdated[@]} == 0)); then
            MSG_OK "All images are up to date"
            return 0
        fi
        local parent pcol GREY='\033[90m'
        for s in "${pending_list[@]}"; do
            parent="$(version_depends "$s" || true)"
            [[ -z "$parent" ]] && parent="external"
            pcol="$YELLOW"
            [[ "$parent" == "external" ]] && pcol="$GREY"
            printf '  %b%s/%s:%s%b  %b%-9s%b(%b%s%b not built yet)\n' \
                "$YELLOW" "$reg" "$(version_image "$s")" "$(version_current "$s")" "$RESET" \
                "$CYAN" "pending" "$RESET" \
                "$pcol" "$parent" "$RESET"
        done
        for s in "${outdated[@]}"; do
            parent="$(version_depends "$s" || true)"
            [[ -z "$parent" ]] && parent="external"
            pcol="$YELLOW"
            [[ "$parent" == "external" ]] && pcol="$GREY"
            printf '  %b%s/%s:%s%b  %b%-9s%b(%b%s%b was rebuilt)\n' \
                "$YELLOW" "$reg" "$(version_image "$s")" "$(version_current "$s")" "$RESET" \
                "$RED" "outdated" "$RESET" \
                "$pcol" "$parent" "$RESET"
        done
    fi
}

# Check if an image hasn't been built yet (state pending/outdated, or version 0.0.0)
needs_building() {
    local s="$1" ini="${2:-$VERSION_INI}"
    local st
    st="$(version_state "$s" "$ini" || true)"
    [[ "$st" == "pending" || "$st" == "outdated" ]] && return 0
    [[ "$(version_current "$s" "$ini" || true)" == "0.0.0" ]] && return 0
    return 1
}

# Collect all transitive deps for a section in build order (leaves first).
collect_deps() {
    local section="$1" max_depth="${2:-20}"
    local -a result=() seen=()
    _cd() {
        local s="$1" depth="${2:-0}"
        ((depth > max_depth)) && return
        for v in "${seen[@]}"; do [[ "$v" == "$s" ]] && return; done
        seen+=("$s")
        local dep_parent
        dep_parent="$(version_depends "$s" || true)"
        if [[ -n "$dep_parent" ]] && needs_building "$dep_parent"; then
            _cd "$dep_parent" $((depth + 1))
        fi
        local predeps_str pd
        predeps_str=$(xget_yml "$RECIPE_DIR/${s}.yml" predep)
        if [[ -n "$predeps_str" ]]; then
            IFS=',' read -ra pd_list <<<"$predeps_str"
            for pd in "${pd_list[@]}"; do
                pd=$(echo "$pd" | xargs)
                [[ -z "$pd" ]] && continue
                needs_building "$pd" || continue
                _cd "$pd" $((depth + 1))
            done
        fi
        for r in "${result[@]}"; do [[ "$r" == "$s" ]] && return; done
        result+=("$s")
    }
    _cd "$section"
    printf '%s\n' "${result[@]}"
}

mark_dependents_outdated() {
    local section="$1" ini="${2:-$VERSION_INI}"
    while IFS= read -r child; do
        [[ -z "$child" ]] && continue
        local child_st
        child_st="$(version_state "$child" "$ini" || true)"
        [[ "$child_st" == "pending" ]] && continue
        ini_set "$child" state outdated "$ini"
    done < <(list_dependents "$section" "$ini" || true)
}

cmd_build() {
    local section="${1:-}" level="${2:-patch}" auto="${3:-}"
    [[ -z "$section" ]] && {
        MSG_NOK "Usage: dvirtmg.sh build <image> [patch|minor|major]"
        return 1
    }
    local ver reg
    ver="$(version_current "$section" || true)"
    reg="$(version_registry)"
    [[ -z "${ver:-}" ]] && {
        MSG_NOK "Unknown image: ${YELLOW}${section}${RESET}"
        return 1
    }

    # First build (0.0.0): auto-bump to 0.0.1 so version.ini + docker tag align.
    if [[ "$ver" == "0.0.0" ]]; then
        ini_set "$section" version 0.0.1 "$VERSION_INI"
        ver="0.0.1"
        # Re-export versions so subsequent builds see the updated value
        source "$IMPORT_DIR/lib/includes/versions.sh"
    fi

    # Collect transitive deps that need building (leaves first)
    local -a deps=()
    while IFS= read -r dep; do
        deps+=("$dep")
    done < <(collect_deps "$section" || true)

    # Build deps — prompt interactively, abort on N
    for dep in "${deps[@]}"; do
        [[ "$dep" == "$section" ]] && continue
        if [[ "$auto" == "auto" ]]; then
            local dep_st
            dep_st="$(version_state "$dep" || true)"
            if [[ "$dep_st" == "outdated" ]]; then
                echo -en "Dependency ${YELLOW}${dep}${RESET} is outdated. Rebuild it? [Y/n] "
                read -r resp
                [[ -z "$resp" || "$resp" =~ ^[yY] ]] || continue
            fi
            cmd_build "$dep" "patch" "auto"
        else
            local resp
            echo -en "Missing dependency ${YELLOW}${dep}${RESET} not built yet. Build it? [Y/n] "
            read -r resp
            [[ -z "$resp" || "$resp" =~ ^[yY] ]] || {
                MSG_NOK "Aborted by user"
                return 1
            }
            cmd_build "$dep" "patch" "auto"
        fi
    done

    # Build the image with current version
    MSG_INFO "Building ${reg}/${section}:${ver}"
    orc_build "$section" || {
        MSG_NOK "Build failed"
        return 1
    }

    # Clear own state
    ini_set "$section" state "" "$VERSION_INI"

    # Record parent version (depends_ver) for interpolation
    local dv_parent
    dv_parent="$(version_depends "$section" || true)"
    if [[ -n "$dv_parent" ]]; then
        ini_set "$section" depends_ver "$(version_current "$dv_parent" || true)" "$VERSION_INI"
    fi

    # Ask to bump (skip in auto mode, skip if immutable)
    if [[ "$auto" == "auto" ]]; then
        : # no bump prompt in auto mode
    elif [[ "$(version_immutable "$section")" == "true" ]]; then
        MSG_INFO "${YELLOW}${section}${RESET} is immutable — locked at ${ver}"
    else
        local resp
        echo -en "Bump ${YELLOW}${section}${RESET} version from ${ver}? [y/N] "
        read -r resp
        if [[ "$resp" =~ ^[yY] ]]; then
            local ini_bak
            ini_bak="$(mktemp "${VERSION_INI}.bak.XXXXXX")"
            cp "$VERSION_INI" "$ini_bak"
            if bump_section "$section" "$level" "$VERSION_INI"; then
                rm -f "$ini_bak"
                source "$IMPORT_DIR/lib/includes/versions.sh"
                MSG_OK "version.ini updated"
            else
                mv "$ini_bak" "$VERSION_INI"
                MSG_NOK "Bump failed; restored backup"
                return 1
            fi
        else
            MSG_INFO "Skipping bump"
        fi
    fi

    # Mark dependents as outdated only when version actually changed
    local new_ver
    new_ver="$(version_current "$section" "$VERSION_INI" || true)"
    if [[ "$ver" != "$new_ver" ]]; then
        mark_dependents_outdated "$section" "$VERSION_INI"
    fi

    # In interactive mode, prompt to rebuild each already-built dependent
    if [[ "$auto" != "auto" ]]; then
        local child child_ver resp
        while IFS= read -r child; do
            [[ -z "$child" ]] && continue
            child_ver="$(version_current "$child" || true)"
            [[ "$child_ver" == "0.0.0" ]] && continue
            echo -en "Rebuild ${YELLOW}${child}${RESET}? [y/N] "
            read -r resp </dev/tty
            [[ "$resp" =~ ^[yY] ]] && cmd_build "$child" "patch" "auto"
        done < <(list_dependents "$section" "$VERSION_INI" || true)
    fi
}

cmd_refresh() {
    generate_version_ini
    source "$IMPORT_DIR/lib/includes/versions.sh"
}

cmd_purge() {
    local target="${1:-}" reg sections img
    reg="$(version_registry)"

    if [[ -n "$target" ]]; then
        MSG_INFO "Removing ${target}..."
        docker images --filter "reference=${reg}/${target}:*" --format '{{.Repository}}:{{.Tag}}' |
            while IFS= read -r tag; do
                docker rmi "$tag" >/dev/null 2>&1 && MSG_OK "Removed ${tag}" || MSG_NOK "Failed to remove ${tag}"
            done
        return 0
    fi

    MSG_INFO "Removing all ${reg} images..."
    local removed=0
    docker images --filter "reference=${reg}/*" --format '{{.Repository}}:{{.Tag}}' |
        while IFS= read -r tag; do
            if docker rmi "$tag" >/dev/null 2>&1; then
                MSG_OK "Removed ${tag}"
            else
                MSG_NOK "Failed to remove ${tag}"
            fi
        done
    docker image prune -f >/dev/null 2>&1 || true
    rm -f "$VERSION_INI"
    MSG_OK "Purge complete — images removed, ${VERSION_INI##*/} deleted"
}

# Auto-generate version.ini if missing
if [[ ! -f "$VERSION_INI" ]]; then
    generate_version_ini
    source "$IMPORT_DIR/lib/includes/versions.sh"
fi

# ── dispatch ────────────────────────────────────────────────────────────────

cmd="${1:-help}"
case "$cmd" in
list) cmd_list ;;
current) cmd_current "${2:-}" ;;
outdated) shift; cmd_outdated "$@" ;;
build) cmd_build "${2:-}" "${3:-patch}" ;;
bump) cmd_build "${2:-}" "${3:-patch}" ;; # alias
refresh) cmd_refresh ;;
purge) cmd_purge "${2:-}" ;;
*)
    cat <<'USAGE'
Usage: dvirtmg.sh <command> [args]

  list                List project images with versions and sizes (default)
  current [image]     Show current version
  outdated [--fix] [image...]   Show pending/outdated images, or rebuild [image(s)] with --fix
  build <image> [lvl] Build image, then optionally bump (patch|minor|major)
  bump                Alias for build
  refresh              Regenerate version.ini from recipe directory
  purge [image]        Remove all or a single project image from local docker
USAGE
    exit 1
    ;;
esac
