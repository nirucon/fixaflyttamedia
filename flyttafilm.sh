#!/bin/bash

VIDEO_EXT=("mp4" "mov" "avi" "mkv" "webm")
VIDEO_COUNT=0
SKIP_COUNT=0
DELETED_COUNT=0
TOTAL_FILES=0
LOG_ENTRIES=()
ORIGINAL_FILES=()

echo "🔍 Kontrollerar beroenden..."
command -v exiftool >/dev/null || { echo "❌ exiftool saknas."; exit 1; }
echo "✅ Alla beroenden är på plats."
echo

read -rp "📂 Ange sökvägen till källmappen: " SOURCE_DIR
[[ ! -d "$SOURCE_DIR" ]] && echo "❌ Ogiltig källmapp." && exit 1

read -rp "📁 Ange sökvägen till målmappen: " DEST_DIR
[[ ! -d "$DEST_DIR" ]] && echo "❌ Ogiltig målmapp." && exit 1

echo
echo "Välj körläge:"
echo "1) 🔍 Dry run – förhandsgranska"
echo "2) ⚡ Live mode – gör ändringar"
read -rp "Ditt val (1 eller 2): " mode

if [[ "$mode" == "1" ]]; then
    DRY_RUN=true
    MODE_LABEL="Dry run"
elif [[ "$mode" == "2" ]]; then
    DRY_RUN=false
    MODE_LABEL="Live mode"
else
    echo "❌ Ogiltigt val. Avbryter."; exit 1
fi

echo
echo "🚀 Startar i läge: $MODE_LABEL"
echo

FIND_CMD="find \"$SOURCE_DIR\" -type f \\( $(printf -- "-iname '*.%s' -o " "${VIDEO_EXT[@]}" | sed 's/ -o $//') \\)"

while read -r FILE; do
    ((TOTAL_FILES++))
    EXT="${FILE##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
    BASENAME=$(basename "$FILE")
    FILESIZE=$(stat -c%s "$FILE")

    [[ " ${VIDEO_EXT[*]} " != *" $EXT_LOWER "* ]] && continue

    if [[ "$FILESIZE" -lt 10485760 ]]; then
        echo "🗑️  Skippas (för liten video <10MB): $FILE"
        LOG_ENTRIES+=("SKIPPED: $FILE (för liten)")
        ((SKIP_COUNT++))
        continue
    fi

    DEST_PATH="$DEST_DIR/$BASENAME"
    COUNT=1
    while [[ -e "$DEST_PATH" ]]; do
        DEST_PATH="$DEST_DIR/${BASENAME%.*}_$COUNT.${EXT_LOWER}"
        ((COUNT++))
    done

    echo "🎬 $FILE → $DEST_PATH"
    LOG_ENTRIES+=("VIDEO: $FILE → $DEST_PATH")

    if [[ "$DRY_RUN" == false ]]; then
        cp "$FILE" "$DEST_PATH"
        ORIGINAL_FILES+=("$FILE")
    fi

    ((VIDEO_COUNT++))
done < <(eval "$FIND_CMD")

echo
echo "============================================="
echo "📊 Sammanfattning"
echo "============================================="
echo "📁 Totalt filer scannade  : $TOTAL_FILES"
echo "🎬 Filmer kopierade        : $VIDEO_COUNT"
echo "⏩ Små videor skippade      : $SKIP_COUNT"
echo "📦 Läge                    : $MODE_LABEL"

if [[ "$DRY_RUN" == false && ${#ORIGINAL_FILES[@]} -gt 0 ]]; then
    echo
    read -rp "🗑️ Vill du radera originalfilerna som har kopierats? (y/n): " del_confirm
    if [[ "$del_confirm" =~ ^[Yy]$ ]]; then
        for f in "${ORIGINAL_FILES[@]}"; do
            rm -f "$f"
        done
        echo "🧹 Originalfiler raderade."
    fi
fi

echo
read -rp "📝 Vill du spara en loggfil? (y/n): " save_log
if [[ "$save_log" =~ ^[Yy]$ ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    LOGFILE="copy_videos_log_$TIMESTAMP.txt"
    printf "%s\n" "${LOG_ENTRIES[@]}" > "$LOGFILE"
    echo "✅ Logg sparad som '$LOGFILE'"
fi

echo
echo "✅ Klar!"
