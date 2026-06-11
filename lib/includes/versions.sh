# versions.sh — Parse version.ini and export env vars.
# version.ini is the single source of truth for all image versions.
#
# Usage: source "$IMPORT_DIR/lib/includes/versions.sh"
# Exports: REGISTRY, SECTION_VERSION, SECTION_IMAGE, SECTION_DEPENDS for every section.

IMPORT_DIR="${IMPORT_DIR:-$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")}"
VERSION_INI="${IMPORT_DIR}/version.ini"

_recipe_candidates=()
[[ -n "${DVIRTD_RECIPE_DIR:-}" ]] && _recipe_candidates+=("$DVIRTD_RECIPE_DIR")
_recipe_candidates+=("$IMPORT_DIR/recipe" "/opt/dvirtd/recipe")

RECIPE_DIR=""
for _candidate in "${_recipe_candidates[@]}"; do
    [[ -d "$_candidate" ]] && [[ -n "$(ls "$_candidate"/*.yml 2>/dev/null)" ]] && {
        RECIPE_DIR="$_candidate"
        break
    }
done

if [[ -z "$RECIPE_DIR" ]]; then
    echo "ERR: No recipes found — tried: ${_recipe_candidates[*]}" >&2
    echo "Set DVIRTD_RECIPE_DIR to a directory with recipe YML files" >&2
    exit 1
fi

unset _recipe_candidates _candidate

# Read a value from version.ini by section and key
ini_get() {
    local section="$1" key="$2" ini="${3:-$VERSION_INI}"
    sed -n "/^\[$section\]/,/^\[/p" "$ini" 2>/dev/null |
        grep "^$key\b" |
        sed 's/^[^=]*=\s*//' |
        tail -1 || true
}

# Current version for a section (e.g. 0.0.6)
version_current() {
    local s="$1" ini="${2:-$VERSION_INI}"
    ini_get "$s" version "$ini"
}

# Image name for a section (without registry prefix, e.g. mirror)
version_image() {
    local s="$1" ini="${2:-$VERSION_INI}"
    ini_get "$s" image "$ini"
}

# Full image prefix (<registry>/<image>, e.g. dvirtd/mirror)
version_image_full() {
    local s="$1" ini="${2:-$VERSION_INI}"
    local reg img
    reg="$(ini_get meta registry "$ini")"
    img="$(ini_get "$s" image "$ini")"
    echo "${reg}/${img}"
}

# Dependency (parent) for a section
version_depends() {
    local s="$1" ini="${2:-$VERSION_INI}"
    ini_get "$s" depends "$ini"
}

# Whether a section is immutable (cannot be bumped)
version_immutable() {
    local s="$1" ini="${2:-$VERSION_INI}"
    ini_get "$s" immutable "$ini"
}

# List all defined image sections
version_sections() {
    local ini="${1:-$VERSION_INI}"
    grep '^\[' "$ini" 2>/dev/null | sed 's/\[//;s/\]//' | grep -v '^meta$'
}

# State (outdated / empty) for a section
version_state() {
    local s="$1" ini="${2:-$VERSION_INI}"
    ini_get "$s" state "$ini"
}

# Registry value
version_registry() {
    local ini="${1:-$VERSION_INI}"
    ini_get meta registry "$ini"
}

# Export registry + version/image/depends for every section
versions_export() {
    local ini="${1:-$VERSION_INI}"
    [[ ! -f "$ini" ]] && return 1
    local reg sections ver img dep var
    reg="$(version_registry "$ini")"
    export REGISTRY="${reg:-dvirtd}"
    sections=$(version_sections "$ini")
    for s in $sections; do
        var=$(echo "$s" | tr 'a-z' 'A-Z' | tr '-' '_')
        ver=$(ini_get "$s" version "$ini")
        img=$(ini_get "$s" image "$ini")
        dep=$(ini_get "$s" depends "$ini")
        dv=$(ini_get "$s" depends_ver "$ini")
        export "${var}_VERSION=$ver"
        export "${var}_IMAGE=$img"
        [[ -n "$dep" ]] && export "${var}_DEPENDS=$dep"
        [[ -n "$dv" ]] && export "${var}_DEPENDS_VER=$dv"
    done
}

# Auto-export when sourced
versions_export
