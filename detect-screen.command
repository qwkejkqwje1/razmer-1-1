#!/bin/bash
# =====================================================================
#  «Размер 1:1» — определение точного физического размера мониторов
#  для macOS и Linux. На Mac: двойной клик (при первом запуске —
#  правый клик → «Открыть»). В Linux: bash detect-screen.command
# =====================================================================
cd "$(dirname "$0")" || exit 1

# Разбор EDID (Linux): файл -> JSON-объект
parse_edid() {
  local b; b=($(od -An -tu1 -v "$1")) ; [ ${#b[@]} -ge 128 ] || return 1
  [ "${b[0]}" = 0 ] && [ "${b[1]}" = 255 ] || return 1
  local o=54
  local x=$(( b[o+2]  + ((b[o+4]  & 0xF0) << 4) )) y=$(( b[o+5]  + ((b[o+7]  & 0xF0) << 4) ))
  local w=$(( b[o+12] + ((b[o+14] & 0xF0) << 4) )) h=$(( b[o+13] + ((b[o+14] & 0x0F) << 8) ))
  if [ $w -lt 50 ] || [ $h -lt 30 ]; then w=$(( b[21]*10 )); h=$(( b[22]*10 )); fi
  local name="" d i c
  for d in 54 72 90 108; do
    if [ "${b[d]}" = 0 ] && [ "${b[d+1]}" = 0 ] && [ "${b[d+3]}" = 252 ]; then
      for ((i=d+5; i<d+18; i++)); do c=${b[i]}; [ "$c" = 10 ] && break; name+=$(printf "\\$(printf %o "$c")"); done
    fi
  done
  name=$(echo "$name" | tr -cd 'A-Za-z0-9 ._+-' | sed 's/ *$//')
  echo "{\"n\":\"$name\",\"w\":$w,\"h\":$h,\"x\":$x,\"y\":$y}"
}

if [ "$(uname)" = "Darwin" ]; then
  # macOS: CGDisplayScreenSize — физический размер в мм (тоже из EDID / паспорта панели)
  JSON=$(osascript -l JavaScript <<'JXA'
ObjC.import('AppKit'); ObjC.import('CoreGraphics');
var r = [], s = $.NSScreen.screens;
for (var i = 0; i < s.count; i++) {
  var sc = s.objectAtIndex(i);
  var id = ObjC.unwrap(sc.deviceDescription.objectForKey('NSScreenNumber'));
  var mm = $.CGDisplayScreenSize(id);
  var name = 'Display ' + (i + 1);
  try { name = ObjC.unwrap(sc.localizedName) || name; } catch (e) {}
  r.push({ n: name, w: Math.round(mm.width * 10) / 10, h: Math.round(mm.height * 10) / 10,
           x: $.CGDisplayPixelsWide(id), y: $.CGDisplayPixelsHigh(id) });
}
JSON.stringify(r);
JXA
)
else
  ITEMS=()
  for d in /sys/class/drm/*/; do
    [ -f "$d/edid" ] && [ "$(cat "$d/status" 2>/dev/null)" = connected ] || continue
    j=$(parse_edid "$d/edid") && ITEMS+=("$j")
  done
  JSON="[$(IFS=,; echo "${ITEMS[*]}")]"
fi

if [ -z "$JSON" ] || [ "$JSON" = "[]" ]; then
  echo "Не удалось прочитать данные монитора. Используйте калибровку по банковской карте."; exit 1
fi
echo "Найдены мониторы: $JSON"
echo "window.SCREEN_EDID = $JSON;" > screen-data.js
CLIP="R11:$JSON"
if command -v pbcopy >/dev/null; then printf %s "$CLIP" | pbcopy
elif command -v wl-copy >/dev/null; then printf %s "$CLIP" | wl-copy
elif command -v xclip >/dev/null; then printf %s "$CLIP" | xclip -selection clipboard; fi
echo "Готово! Данные сохранены в screen-data.js (и в буфер обмена). Открываю программу..."
if command -v open >/dev/null; then open razmer.html; else xdg-open razmer.html >/dev/null 2>&1 & fi
