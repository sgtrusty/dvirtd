# Xephyr display management

dpy_next_available() {
    local max=0 n
    for d in /tmp/.X11-unix/X*; do
        n="${d##*/X}"
        (( n > max )) && max=$n
    done
    echo ":$((max + 1))"
}

dpy_xephyr_mount() {
    local display="${1:-:0}"
    if [[ "$display" != ":0" ]]; then
        echo "-v /tmp/.X11-unix/X${display#:}:/tmp/.X11-unix/X${display#:}"
    fi
}

dpy_start_xephyr() {
    local display="${1:-:0}" size="${2:-1024x768}" opts="${3:--no-host-grab}"
    local appname="${4:-archdevel}"
    [[ "$display" == ":0" ]] && return 0
    MSG_INFO "Starting Xephyr on ${display} @ ${size}"
    Xephyr "$display" "$opts" -ac -br -screen "$size" -resizeable -reset -terminate &
    local window_id=""
    while [[ -z "$window_id" ]]; do
        window_id=$(xdotool search --name "Xephyr on ${display}.0" 2>/dev/null || true)
        sleep 1
    done
    MSG_OK "Starting Xephyr on display ${display}"
    xdotool set_window --name "$appname" "$window_id"
}
