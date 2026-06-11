postfx() {
    while ! pidof ${WINMAG} >/dev/null; do sleep 1; done
    exec ${ENTRY_APP}
}

if [[ -n "$ENTRY_VARS" ]]; then
    set -a
    eval $ENTRY_VARS
    set +a
fi

cd "${ENTRY_DIR:-/home/archlinux/shared}"

if [[ ${PERSIST:-1} == 1 ]]; then
    if [[ ${WINMAG} && ${WINMAG} != 0 ]]; then
        postfx <&0 &
        ${WINMAG}
    fi
else
    [[ ${WINMAG} && ${WINMAG} != 0 ]] && ${WINMAG} &
    postfx <&0
fi
