function cache_selection() {
    CACHE_DIR=$1
    TARGET=$2

    if [ ! -d $CACHE_DIR ]; then
        mkdir $CACHE_DIR
    fi
    ALL_CHOICES=""
    CHOICE=""
    TO_FILE=${CACHE_DIR}/${TARGET}
    if [ -e $TO_FILE ]; then
        ALL_CHOICES=$(cat $TO_FILE)
        CHOICE=$(sed '/./,$!d' <<< $ALL_CHOICES | rofi -dmenu -p "Enter Text > " -sep '\n')
    fi
    if [ -z "$CHOICE" ]; then
        # CHOICE=$(rofi -dmenu -p "Enter Text > " -theme-str 'listview { enabled: false;}')
        # CHOICE=$(find * -type d | fzf)
        source $IMPORT_DIR/lib/includes/explorer_find.sh
	explorer_find_mkwin
        CHOICE=$(explorer_find_get)
        ALL_CHOICES=$(echo -e "$ALL_CHOICES" | tac)
        echo -e "${ALL_CHOICES}\n${CHOICE}" | sed '/./,$!d' | tac | awk '!a[$0]++' | head -n10 > $TO_FILE
    fi

    echo $CHOICE
}
