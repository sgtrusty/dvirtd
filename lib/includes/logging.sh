# ANSI color codes
# Reset color
RESET='\033[0m'

# Regular colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Bold colors
BOLD_BLACK='\033[1;30m'
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'
BOLD_MAGENTA='\033[1;35m'
BOLD_CYAN='\033[1;36m'
BOLD_WHITE='\033[1;37m'

SPACE_STACK=0

# Function to generate tab string
generate_tabs() {
    if [ $SPACE_STACK -ne 0 ]; then
        local tabs=$(printf '\t%.0s' $(seq 1 "$SPACE_STACK"))
        echo -n "$tabs"
    fi
}

DATETIME() {
    # captured_text="${PIPESTATUS[@]}" 
    echo -n "[$(date -Is)]";
}

# Function to display success/fail message with variable number of tabs
__MSG() {
    if [ $SPACE_STACK -eq 0 ]; then
        ((SPACE_STACK = SPACE_STACK + 1))
    fi

    local tabs=$(generate_tabs)
    local color
    local status
    if [ "$1" = "OK" ]; then
        color="${BOLD_GREEN}"
        status="OK"
        ((SPACE_STACK = SPACE_STACK > 0 ? SPACE_STACK - 1 : 0))
    elif [ "$1" = "NOK" ]; then
        color="${BOLD_RED}"
        status="NOK"
        ((SPACE_STACK = SPACE_STACK > 0 ? SPACE_STACK - 1 : 0))
    else
        color="${BOLD_WHITE}"
        status="RUNNING"
    fi
    echo -e "${color}${tabs}-> $(DATETIME) ${RESET}$2 ... ${color}$status${RESET}"
}

MSG() {
    __MSG DEFAULT "$1"
}

MSG_OK() {
    if [ -n "${2:-}" ]; then
        printf '\e[A\e[K'
    fi
    __MSG OK "$1"
}

MSG_NOK() {
    if [ -n "${2:-}" ]; then
        printf '\e[A\e[K'
    fi
    __MSG NOK "$1"
}

# Function to display info message
MSG_INFO() {
    if [ -n "${2:-}" ]; then
        ((SPACE_STACK = SPACE_STACK + 1))
    fi
    local tabs=$(generate_tabs)
    echo -e "${tabs}${BLUE}$(DATETIME) INFO:${RESET} $1"
    ((SPACE_STACK = SPACE_STACK + 1))
}

# LOGFILE="log.log"
# exec 3>&1 1>"$LOGFILE" 2>&1
# trap "echo 'ERROR: An error occurred during execution, check log $LOGFILE for details.' >&3" ERR
# trap '{ set +x; } 2>/dev/null; echo -n "[$(date -Is)]  "; set -x' DEBUG
trapme() {
    trap 'DATETIME' DEBUG
}