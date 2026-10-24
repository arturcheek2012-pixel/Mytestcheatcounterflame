#!/bin/bash
D=$1
shopt -s nullglob
for f in "$D"/*.dylib; do
  install_name_tool -id "@loader_path/$(basename "$f")" "$f" || true
  for dep in $(otool -L "$f" | tail -n +2 | awk '{print $1}'); do
    b=$(basename "$dep")
    if [ -f "$D/$b" ] && [ "$dep" != "@loader_path/$b" ]; then
      install_name_tool -change "$dep" "@loader_path/$b" "$f" || true
    fi
  done
  codesign -f -s - "$f" || true
done
exit 0
