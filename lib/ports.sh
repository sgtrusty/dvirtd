# ── host port reservation: availability checks + injection ───────────────
# Recipes declare preferred ports ONLY in x-dvirtd (ports: 3000,5173,...).
# port_inject resolves each to a free host port and appends a generated
# ports: block to the launch copy — committed recipes stay portless.
#
# Two resolution modes:
#   default            — per-port preference: P if free, else next free ≥ P
#   DVIRTD_PORT_BASE=N — anchored block: identity-mapped ports (W:W) laid
#                        onto the first free contiguous run starting at N
#                        (useport[N] cmdopt)

PORTS_TAKEN=""

yml_xget() {
    local yml="$1" key="$2"
    [[ -f "$yml" ]] || return 0
    sed -n '/^x-dvirtd:/,/^[a-z#]/p' "$yml" 2>/dev/null |
        grep -E "^  ${key}:" | sed 's/^  [^:]*:[[:space:]]*//' | head -1 || true
}

port_in_use() {
    local p="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltnH "( sport = :$p )" 2>/dev/null | grep -q . && return 0
        return 1
    fi
    (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
    return 1
}

ports_batch_has() {
    [[ " $PORTS_TAKEN " == *" $1 "* ]]
}

# Echo the first free port >= $1, skipping ports claimed earlier this batch.
port_claim() {
    local p="$1"
    local cap=$((p + 100))
    while ((p <= cap)); do
        if ! port_in_use "$p" && ! ports_batch_has "$p"; then
            echo "$p"
            return 0
        fi
        ((p++))
    done
    return 1
}

# Resolve declared ports for a compose file and append a generated ports:
# block to it. Falls back through one extends: file: hop when the yml has
# no declaration.
port_inject() {
    local yml="$1" decl p want ext dir base="${DVIRTD_PORT_BASE:-}" cursor
    decl="$(yml_xget "$yml" ports)"
    if [[ -z "$decl" ]]; then
        ext="$(sed -n '/extends:/,/^[a-z#]/p' "$yml" 2>/dev/null |
            sed -n 's/.*file:[[:space:]]*//p' | head -1 || true)"
        if [[ -n "$ext" ]]; then
            [[ "$ext" == /* ]] || { dir="$(dirname "$yml")"; ext="$dir/$ext"; }
            [[ -f "$ext" ]] && decl="$(yml_xget "$ext" ports)"
        fi
    fi
    [[ -z "$decl" ]] && {
        MSG_INFO "No ports declared for ${yml##*/} — skipping reservation"
        return 0
    }
    PORTS_TAKEN=""
    cursor="$base"
    local lines=()
    local IFS=','
    for p in $decl; do
        p="${p//[[:space:]]/}"
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        if [[ -n "$base" ]]; then
            want="$(port_claim "$cursor")" || {
                MSG_NOK "No free port ≥ $cursor"
                return 1
            }
            cursor=$((want + 1))
            MSG_INFO "container $want → host $want (block from $base)"
        else
            want="$(port_claim "$p")" || {
                MSG_NOK "No free port ≥ $p"
                return 1
            }
            if [[ "$want" == "$p" ]]; then
                MSG_OK "Reserved port $p"
            else
                MSG_INFO "Port $p busy — reserved $want instead"
            fi
        fi
        PORTS_TAKEN+=" $want"
        lines+=("      - \"127.0.0.1:${want}:${want}\"")
    done
    ((${#lines[@]})) || return 0
    {
        echo ""
        echo "    ports:"
        printf '%s\n' "${lines[@]}"
    } >>"$yml"
}
