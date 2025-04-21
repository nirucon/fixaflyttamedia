
#!/bin/bash

PHOTO_EXT=("jpg" "jpeg" "png" "heic")
PHOTO_COUNT=0
SKIP_COUNT=0
CONVERT_COUNT=0
DELETED_COUNT=0
TOTAL_FILES=0
UNKNOWN_COUNT=0
LOG_ENTRIES=()
ORIGINAL_FILES=()

echo "🔍 Kontrollerar beroenden..."
command -v exiftool >/dev/null || { echo "❌ exiftool saknas."; exit 1; }
if ! command -v magick >/dev/null && ! command -v heif-convert >/dev/null; then
    echo "❌ magick eller heif-convert krävs."; exit 1
fi
echo "✅ Alla beroenden är på plats."
echo

read -rp "📂 Ange sökvägen till källmappen: " SOURCE_DIR
[[ ! -d "$SOURCE_DIR" ]] && echo "❌ Ogiltig källmapp." && exit 1

read -rp "📁 Ange sökvägen till målmappen: " DEST_ROOT
[[ ! -d "$DEST_ROOT" ]] && echo "❌ Ogiltig målmapp." && exit 1

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

FIND_CMD="find \"$SOURCE_DIR\" -type f \\( $(printf -- "-iname '*.%s' -o " "${PHOTO_EXT[@]}" | sed 's/ -o $//') \\)"

while read -r FILE; do
    ((TOTAL_FILES++))
    EXT="${FILE##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
    REL_PATH="${FILE#$SOURCE_DIR/}"

    [[ " ${PHOTO_EXT[*]} " != *" $EXT_LOWER "* ]] && continue

    DEST_PATH="$DEST_ROOT/$REL_PATH"
    DEST_DIR=$(dirname "$DEST_PATH")
    mkdir -p "$DEST_DIR"

    echo "📷 $FILE → $DEST_PATH"
    LOG_ENTRIES+=("PHOTO: $FILE → $DEST_PATH")

    if [[ "$DRY_RUN" == false ]]; then
        if [[ "$EXT_LOWER" == "heic" ]]; then
            DEST_PATH="${DEST_PATH%.*}.jpeg"
            if command -v magick >/dev/null; then
                magick "$FILE" "$DEST_PATH"
            else
                heif-convert "$FILE" "$DEST_PATH" >/dev/null
            fi
            ((CONVERT_COUNT++))
        else
            cp "$FILE" "$DEST_PATH"
        fi
        ORIGINAL_FILES+=("$FILE")
    fi

    ((PHOTO_COUNT++))
done < <(eval "$FIND_CMD")

echo
echo "============================================="
echo "📊 Sammanfattning"
echo "============================================="
echo "📁 Totalt filer scannade  : $TOTAL_FILES"
echo "🖼️  Foton kopierade        : $PHOTO_COUNT"
echo "🔄 HEIC konverterade       : $CONVERT_COUNT"
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
    LOGFILE="copy_photos_log_$TIMESTAMP.txt"
    printf "%s\n" "${LOG_ENTRIES[@]}" > "$LOGFILE"
    echo "✅ Logg sparad som '$LOGFILE'"
fi

echo
echo "✅ Klar!"
