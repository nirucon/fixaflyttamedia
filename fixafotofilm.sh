#!/bin/bash

set -e

SOURCE_DIR="$1"
DRY_RUN=false
LOG_FILE="organize_photos.log"

if [[ "$2" == "--dry-run" || "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[Dry Run] Inget kommer att flyttas eller ändras." | tee -a "$LOG_FILE"
fi

if [[ -z "$SOURCE_DIR" || "$SOURCE_DIR" == "--dry-run" ]]; then
  echo "Användning: $0 <källmapp> [--dry-run]"
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "❌ Fel: Mappen '$SOURCE_DIR' finns inte."
  exit 1
fi

# Kontroll av beroenden
command -v exiftool >/dev/null || { echo "❌ exiftool saknas."; exit 1; }
if ! command -v magick >/dev/null && ! command -v heif-convert >/dev/null; then
  echo "❌ Behöver 'magick' (ImageMagick) eller 'heif-convert' för HEIC-konvertering."
  exit 1
fi

echo "📂 Söker i: $SOURCE_DIR" | tee "$LOG_FILE"

find "$SOURCE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" \) | while read -r FILE; do
  EXT="${FILE##*.}"
  EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
  BASENAME=$(basename "$FILE")

  DATETIME=$(exiftool -d "%Y%m%d_%H%M%S" -DateTimeOriginal -S -s "$FILE" 2>/dev/null | head -n1)

  if [[ -z "$DATETIME" ]]; then
    DEST_DIR="$SOURCE_DIR/unknown"
    NEWFILE="$BASENAME"
    mkdir -p "$DEST_DIR"
    DEST_PATH="$DEST_DIR/$NEWFILE"
    echo "⚠️  Ingen metadata: $FILE -> $DEST_PATH" | tee -a "$LOG_FILE"
    if ! $DRY_RUN; then cp "$FILE" "$DEST_PATH"; fi
    continue
  fi

  DATE_PART="${DATETIME:0:8}"         # YYYYMMDD
  TIME_PART="${DATETIME:9:6}"         # HHMMSS
  YEAR="${DATE_PART:0:4}"
  MONTH="${DATE_PART:4:2}"
  DAY="${DATE_PART:6:2}"
  DEST_DIR="$SOURCE_DIR/$YEAR/$MONTH/$DAY"
  mkdir -p "$DEST_DIR"

  NEWNAME="${DATE_PART}_${TIME_PART}.jpeg"
  DEST_PATH="$DEST_DIR/$NEWNAME"

  # Om fil redan finns, lägg till suffix
  COUNTER=1
  while [[ -e "$DEST_PATH" ]]; do
    DEST_PATH="$DEST_DIR/${DATE_PART}_${TIME_PART}_$COUNTER.jpeg"
    ((COUNTER++))
  done

  echo "📸 $FILE → $DEST_PATH" | tee -a "$LOG_FILE"

  if $DRY_RUN; then continue; fi

  if [[ "$EXT_LOWER" == "heic" ]]; then
    if command -v magick >/dev/null; then
      magick "$FILE" "$DEST_PATH"
    else
      heif-convert "$FILE" "$DEST_PATH" >/dev/null
    fi
  else
    convert "$FILE" "$DEST_PATH" 2>/dev/null || cp "$FILE" "$DEST_PATH"
  fi
done

echo "✅ Klar! Logg sparad i $LOG_FILE"
