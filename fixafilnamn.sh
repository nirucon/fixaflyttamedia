#!/bin/bash

PHOTO_EXT=("jpg" "jpeg" "png" "heic")
VIDEO_EXT=("mp4" "mov" "avi" "mkv" "webm")
RENAME_COUNT=0
SKIPPED_COUNT=0
CONVERT_COUNT=0
LOG_ENTRIES=()

echo "🔍 Kontrollerar beroenden..."
command -v exiftool >/dev/null || { echo "❌ exiftool saknas."; exit 1; }

if ! command -v magick >/dev/null && ! command -v heif-convert >/dev/null; then
    echo "❌ magick eller heif-convert krävs för HEIC-konvertering."; exit 1
fi
echo "✅ Alla beroenden är på plats."
echo

read -rp "📁 Ange mapp med filer att byta namn på: " TARGET_DIR
[[ ! -d "$TARGET_DIR" ]] && echo "❌ Ogiltig mapp." && exit 1

echo
echo "Vad vill du byta namn på?"
echo "1) 📷 Endast foton"
echo "2) 🎬 Endast filmer"
echo "3) 📷🎬 Både foton och filmer"
read -rp "Ditt val (1/2/3): " choice

RENAME_PHOTOS=false
RENAME_VIDEOS=false
case "$choice" in
    1) RENAME_PHOTOS=true ;;
    2) RENAME_VIDEOS=true ;;
    3) RENAME_PHOTOS=true; RENAME_VIDEOS=true ;;
    *) echo "❌ Ogiltigt val."; exit 1 ;;
esac

echo
echo "🚀 Startar namnändring och eventuell konvertering..."

find "$TARGET_DIR" -maxdepth 1 -type f | while read -r FILE; do
    EXT="${FILE##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
    BASENAME=$(basename "$FILE")
    DIRNAME=$(dirname "$FILE")

    IS_PHOTO=false
    IS_VIDEO=false

    [[ " ${PHOTO_EXT[*]} " == *" $EXT_LOWER "* ]] && IS_PHOTO=true
    [[ " ${VIDEO_EXT[*]} " == *" $EXT_LOWER "* ]] && IS_VIDEO=true
    [[ "$IS_PHOTO" = false && "$IS_VIDEO" = false ]] && continue

    [[ "$IS_PHOTO" == true && "$RENAME_PHOTOS" == false ]] && continue
    [[ "$IS_VIDEO" == true && "$RENAME_VIDEOS" == false ]] && continue

    DATETIME=""
    if [[ "$IS_PHOTO" == true ]]; then
        DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -DateTimeOriginal -S -s "$FILE" 2>/dev/null)
        [[ -z "$DATETIME" ]] && DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -CreateDate -S -s "$FILE" 2>/dev/null)
    elif [[ "$IS_VIDEO" == true ]]; then
        DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -MediaCreateDate -S -s "$FILE" 2>/dev/null)
        [[ -z "$DATETIME" ]] && DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -FileModifyDate -S -s "$FILE" 2>/dev/null)
    fi

    if [[ -z "$DATETIME" ]]; then
        echo "⚠️  Skippas – inget datum: $BASENAME"
        LOG_ENTRIES+=("SKIPPED: $BASENAME – inget datum")
        ((SKIPPED_COUNT++))
        continue
    fi

    # HEIC-konvertering
    if [[ "$EXT_LOWER" == "heic" ]]; then
        NEW_NAME="${DATETIME}.jpeg"
        DEST_PATH="$DIRNAME/$NEW_NAME"
        COUNT=1
        while [[ -e "$DEST_PATH" ]]; do
            DEST_PATH="$DIRNAME/${DATETIME}_$COUNT.jpeg"
            ((COUNT++))
        done

        echo "🔄 Konverterar & döper: $BASENAME → $(basename "$DEST_PATH")"
        if command -v magick >/dev/null; then
            magick "$FILE" "$DEST_PATH"
        else
            heif-convert "$FILE" "$DEST_PATH" >/dev/null
        fi
        rm -f "$FILE"
        ((RENAME_COUNT++))
        ((CONVERT_COUNT++))
        LOG_ENTRIES+=("CONVERTED: $BASENAME → $(basename "$DEST_PATH")")
        continue
    fi

    # Vanlig namnändring
    NEW_NAME="${DATETIME}.${EXT_LOWER}"
    DEST_PATH="$DIRNAME/$NEW_NAME"
    COUNT=1
    while [[ -e "$DEST_PATH" && "$DEST_PATH" != "$FILE" ]]; do
        DEST_PATH="$DIRNAME/${DATETIME}_$COUNT.${EXT_LOWER}"
        ((COUNT++))
    done

    if [[ "$FILE" != "$DEST_PATH" ]]; then
        echo "✏️  $BASENAME → $(basename "$DEST_PATH")"
        mv "$FILE" "$DEST_PATH"
        LOG_ENTRIES+=("RENAMED: $BASENAME → $(basename "$DEST_PATH")")
        ((RENAME_COUNT++))
    fi
done

echo
echo "============================================="
echo "📊 Sammanfattning"
echo "============================================="
echo "🔄 Filer bytte namn        : $RENAME_COUNT"
echo "🔁 HEIC konverterade       : $CONVERT_COUNT"
echo "⏭️  Skippade (utan datum)   : $SKIPPED_COUNT"
echo

read -rp "📝 Vill du spara en loggfil? (y/n): " save_log
if [[ "$save_log" =~ ^[Yy]$ ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    LOGFILE="rename_log_$TIMESTAMP.txt"
    printf "%s\n" "${LOG_ENTRIES[@]}" > "$LOGFILE"
    echo "✅ Logg sparad som '$LOGFILE'"
fi

echo
echo "✅ Klar!"
