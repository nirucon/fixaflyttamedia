#!/bin/bash

SUPPORTED_EXT=("jpg" "jpeg" "png" "heic")
RENAME_COUNT=0
SKIP_COUNT=0
CONVERT_COUNT=0
TOTAL_COUNT=0
UNKNOWN_COUNT=0
LOG_ENTRIES=()
SKIPPED_FILES=()
CONVERTED_FILES=()

echo "🔍 Kontrollerar beroenden..."
command -v exiftool >/dev/null || { echo "❌ exiftool saknas."; exit 1; }
if ! command -v magick >/dev/null && ! command -v heif-convert >/dev/null; then
    echo "❌ magick eller heif-convert krävs."; exit 1
fi
echo "✅ Alla beroenden är på plats."
echo

read -rp "📂 Ange sökvägen till mappen med foton: " SOURCE_DIR
[[ ! -d "$SOURCE_DIR" ]] && echo "❌ Ogiltig mapp." && exit 1

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
echo "🧪 Sökväg: $SOURCE_DIR"
echo

FIND_CMD="find \"$SOURCE_DIR\" -type f \\( $(printf -- "-iname '*.%s' -o " "${SUPPORTED_EXT[@]}" | sed 's/ -o $//') \\)"

while read -r FILE; do
    ((TOTAL_COUNT++))
    EXT="${FILE##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
    BASENAME=$(basename "$FILE")

    DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -DateTimeOriginal -S -s "$FILE" 2>/dev/null)
    [[ -z "$DATETIME" ]] && DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -CreateDate -S -s "$FILE" 2>/dev/null)
    [[ -z "$DATETIME" ]] && DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -FileModifyDate -S -s "$FILE" 2>/dev/null)

    if [[ -z "$DATETIME" ]]; then
        ((UNKNOWN_COUNT++))
        DEST_DIR="$SOURCE_DIR/unknown"
        mkdir -p "$DEST_DIR"
        DEST_PATH="$DEST_DIR/$BASENAME"
        echo "⚠️  Ingen giltig datumdata: $FILE → $DEST_PATH"
        LOG_ENTRIES+=("SKIPPED: $FILE → unknown/")
        SKIPPED_FILES+=("$FILE")
        [[ "$DRY_RUN" == false ]] && cp "$FILE" "$DEST_PATH"
        continue
    fi

    DATE_PART="${DATETIME:0:8}"  # YYYYMMDD
    TIME_PART="${DATETIME:9:6}"  # HHMMSS
    YEAR="${DATE_PART:0:4}"
    MONTH="${DATE_PART:4:2}"
    DAY="${DATE_PART:6:2}"
    DEST_DIR="$SOURCE_DIR/$YEAR/$MONTH/$DAY"
    mkdir -p "$DEST_DIR"

    FILENAME_BASE="${DATE_PART}_${TIME_PART}"
    DEST_PATH="$DEST_DIR/$FILENAME_BASE.jpeg"

    COUNT=1
    while [[ -e "$DEST_PATH" ]]; do
        DEST_PATH="$DEST_DIR/${FILENAME_BASE}_$COUNT.jpeg"
        ((COUNT++))
    done

    echo "📸 $FILE → $DEST_PATH"
    LOG_ENTRIES+=("OK: $FILE → $DEST_PATH")

    if [[ "$DRY_RUN" == false ]]; then
        if [[ "$EXT_LOWER" == "heic" ]]; then
            if command -v magick >/dev/null; then
                magick "$FILE" "$DEST_PATH"
            else
                heif-convert "$FILE" "$DEST_PATH" >/dev/null
            fi
            ((CONVERT_COUNT++))
            CONVERTED_FILES+=("$FILE")
        else
            cp "$FILE" "$DEST_PATH"
        fi
        ((RENAME_COUNT++))
    fi
done < <(eval "$FIND_CMD")

echo
echo "============================================="
echo "📊 Sammanfattning"
echo "============================================="
echo "📁 Total antal filer       : $TOTAL_COUNT"
echo "🖼️  Organiserade bilder     : $RENAME_COUNT"
echo "🔄 HEIC konverterade       : $CONVERT_COUNT"
echo "⚠️  Saknade EXIF (unknown)  : $UNKNOWN_COUNT"
echo "📦 Läge                    : $MODE_LABEL"

if [ ${#SKIPPED_FILES[@]} -gt 0 ]; then
    echo
    echo "⚠️  Filer utan giltigt datum:"
    for f in "${SKIPPED_FILES[@]}"; do
        echo "   - $f"
    done
fi

echo
read -rp "📝 Vill du spara en loggfil? (y/n): " save_log
if [[ "$save_log" =~ ^[Yy]$ ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    LOGFILE="organize_photos_log_$TIMESTAMP.txt"
    printf "%s\n" "${LOG_ENTRIES[@]}" > "$LOGFILE"
    echo "✅ Logg sparad som '$LOGFILE'"
fi

echo
echo "✅ Klar!"
