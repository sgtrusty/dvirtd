# Env var assembly for docker-compose
# Outputs space-separated KEY="val" pairs for prefixing to docker-compose commands

ENV_VARS_ENUM="SHARED_VOLUME PREF_VOLUME SAFECODE_TMP ENTRY_APP ENTRY_VARS ENTRY_DIR PERSIST APPDISPLAY WINMAG"

env_assemble() {
    local var out=""
    for var in $ENV_VARS_ENUM; do
        if [[ -n "${!var:-}" ]]; then
            out+=" ${var}=\"${!var}\""
        fi
    done
    echo "$out"
}
