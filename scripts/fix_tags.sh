#!/bin/bash

DIRECTORY="rest_api"

if [ ! -d "$DIRECTORY" ]; then
  echo "Directory $DIRECTORY does not exist."
  exit 1
fi

find "$DIRECTORY" -type f -name "*.adoc" -exec sed -i.bak -E 's/Next_available_tag__([0-9]+)/NextAvailableTag\1/g; s/Next_Tag__([0-9]+)/NextTag\1/g' {} +

find "$DIRECTORY" -type f -name "*.adoc" | while read -r file; do
  if [ -f "$file.bak" ]; then
    CHANGES=$(diff -u "$file.bak" "$file" | grep -E '^\+' | grep -vE '^\+\+\+' | wc -l)
    if [ "$CHANGES" -gt 0 ]; then
      echo "Fixed incorrect tags in: $file, Change count: $CHANGES"
    fi
    rm "$file.bak"
  fi
done
