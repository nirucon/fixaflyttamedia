#!/bin/bash

PHOTO_EXT=("jpg" "jpeg" "png" "heic")
VIDEO_EXT=("mp4" "mov" "avi" "mkv" "webm")
PHOTO_COUNT=0
VIDEO_COUNT=0
CONVERT_COUNT=0
SKIP_COUNT=0
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

echo
echo "Vad vill du kopiera?"
echo "1) 📷 Endast foton"
echo "2) 🎬 Endast filmer"
echo "3) 📷🎬 Både foton och filmer"
read -rp "Ditt val (1/2/3): " copy_choice

COPY_PHOTOS=false
COPY_VIDEOS=false
case "$copy_choice" in
    1) COPY_PHOTOS=true ;;
    2) COPY_VIDEOS=true ;;
    3) COPY_PHOTOS=true; COPY_VIDEOS=true ;;
    *) echo "❌ Ogiltigt val."; exit 1 ;;
esac

if [[ "$COPY_PHOTOS" == true ]]; then
    read -rp "📁 Ange målmapp för FOTON (med struktur): " PHOTO_DEST
    [[ ! -d "$PHOTO_DEST" ]] && echo "❌ Ogiltig fotomapp." && exit 1
fi

if [[ "$COPY_VIDEOS" == true ]]; then
    read -rp "📁 Ange målmapp för FILMER (utan struktur): " VIDEO_DEST
    [[ ! -d "$VIDEO_DEST" ]] && echo "❌ Ogiltig filmmapp." && exit 1
fi

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

ALL_EXT=("${PHOTO_EXT[@]}" "${VIDEO_EXT[@]}")
FIND_CMD="find \"$SOURCE_DIR\" -type f \\( $(printf -- "-iname '*.%s' -o " "${ALL_EXT[@]}" | sed 's/ -o $//') \\)"

while read -r FILE; do
    ((TOTAL_FILES++))
    EXT="${FILE##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
    FILESIZE=$(stat -c%s "$FILE")
    BASENAME=$(basename "$FILE")

    IS_PHOTO=false
    IS_VIDEO=false

    [[ " ${PHOTO_EXT[*]} " == *" $EXT_LOWER "* ]] && IS_PHOTO=true
    [[ " ${VIDEO_EXT[*]} " == *" $EXT_LOWER "* ]] && IS_VIDEO=true
    [[ "$IS_PHOTO" = false && "$IS_VIDEO" = false ]] && continue

    # Få datum från EXIF eller filinfo
    DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -DateTimeOriginal -S -s "$FILE" 2>/dev/null)
    [[ -z "$DATETIME" ]] && DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -CreateDate -S -s "$FILE" 2>/dev/null)
    [[ -z "$DATETIME" ]] && DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -FileModifyDate -S -s "$FILE" 2>/dev/null)

    if [[ -z "$DATETIME" ]]; then
        ((UNKNOWN_COUNT++))
        LOG_ENTRIES+=("SKIPPED: $FILE – saknar datum")
        continue
    fi

    DATE_PART="${DATETIME:0:8}"  # YYYYMMDD
    TIME_PART="${DATETIME:9:6}"  # HHMMSS
    FILENAME_BASE="${DATE_PART}_${TIME_PART}"

    if [[ "$IS_PHOTO" == true && "$COPY_PHOTOS" == true ]]; then
        DEST_FOLDER="$PHOTO_DEST/${DATE_PART:0:4}/${DATE_PART:4:2}/${DATE_PART:6:2}"
        DEST_PATH="$DEST_FOLDER/$FILENAME_BASE.jpeg"

        COUNT=1
        while [[ -e "$DEST_PATH" ]]; do
            DEST_PATH="$DEST_FOLDER/${FILENAME_BASE}_$COUNT.jpeg"
            ((COUNT++))
        done

        echo "📷 $FILE → $DEST_PATH"
        LOG_ENTRIES+=("PHOTO: $FILE → $DEST_PATH")

        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$DEST_FOLDER"
            if [[ "$EXT_LOWER" == "heic" ]]; then
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

    elif [[ "$IS_VIDEO" == true && "$COPY_VIDEOS" == true ]]; then
        if [[ "$FILESIZE" -lt 10485760 ]]; then
            echo "🗑️  Raderar liten video (<10MB): $FILE"
            LOG_ENTRIES+=("DELETED: $FILE (för liten)")
            ((DELETED_COUNT++))
            if [[ "$DRY_RUN" == false ]]; then
                rm -f "$FILE"
            fi
            continue
        fi

        DEST_PATH="$VIDEO_DEST/$FILENAME_BASE.${EXT_LOWER}"
        COUNT=1
        while [[ -e "$DEST_PATH" ]]; do
            DEST_PATH="$VIDEO_DEST/${FILENAME_BASE}_$COUNT.${EXT_LOWER}"
            ((COUNT++))
        done

        echo "🎬 $FILE → $DEST_PATH"
        LOG_ENTRIES+=("VIDEO: $FILE → $DEST_PATH")

        if [[ "$DRY_RUN" == false ]]; then
            cp "$FILE" "$DEST_PATH"
            ORIGINAL_FILES+=("$FILE")
        fi
        ((VIDEO_COUNT++))
    fi
done < <(eval "$FIND_CMD")

echo
echo "============================================="
echo "📊 Sammanfattning"
echo "============================================="
echo "📁 Totalt filer scannade     : $TOTAL_FILES"
echo "🖼️  Foton kopierade           : $PHOTO_COUNT"
echo "🎬 Filmer kopierade           : $VIDEO_COUNT"
echo "🔄 HEIC konverterade          : $CONVERT_COUNT"
echo "🗑️  Små filmer raderade        : $DELETED_COUNT"
echo "⚠️  Saknade EXIF-datum         : $UNKNOWN_COUNT"
echo "📦 Läge                       : $MODE_LABEL"

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
    LOGFILE="copy_combined_log_$TIMESTAMP.txt"
    printf "%s\n" "${LOG_ENTRIES[@]}" > "$LOGFILE"
    echo "✅ Logg sparad som '$LOGFILE'"
fi

echo
echo "✅ Klar!"
