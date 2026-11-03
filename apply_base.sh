#!/usr/bin/env bash
# Menerapkan dasar PPSSPP Openvpn ke source PPSSPP 1.20.4 (dengan submodule).
# Pakai: ./apply_base.sh /path/ke/ppsspp
# Opsional: OPENVPN_APP_ID (default id.openvpn.ppsspp), OPENVPN_APP_NAME (default "PPSSPP Openvpn")
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:?Pakai: apply_base.sh <folder ppsspp>}"
NEW_ID="${OPENVPN_APP_ID:-id.openvpn.ppsspp}"
NEW_NAME="${OPENVPN_APP_NAME:-PPSSPP Openvpn}"

# 1. Ganti file pause screen (tab Web Mirror + tombol Multiplayer)
cp "$HERE/PauseScreen.cpp" "$SRC/UI/PauseScreen.cpp"
cp "$HERE/PauseScreen.h"   "$SRC/UI/PauseScreen.h"

# 2. Package name baru (namespace Java/JNI TIDAK diubah, hanya applicationId)
G="$SRC/android/build.gradle.kts"
grep -q 'applicationId = "org.ppsspp.ppsspp"' "$G" || { echo "applicationId asli tidak ditemukan"; exit 1; }
sed -i "s/applicationId = \"org.ppsspp.ppsspp\"/applicationId = \"$NEW_ID\"/g" "$G"

# 3. Opsi build hanya ARM64 (lebih cepat) lewat -POPENVPN_ARM64_ONLY=true
python3 - "$G" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))'
assert old in s, "abiFilters asli tidak ditemukan"
new = 'if (project.hasProperty("OPENVPN_ARM64_ONLY")) { abiFilters.add("arm64-v8a") } else { ' + old + ' }'
s = s.replace(old, new, 1)
open(p, 'w').write(s)
PY

# 4. Nama aplikasi
STR="$SRC/android/res/values/strings.xml"
grep -q '<string name="app_name">PPSSPP</string>' "$STR" || { echo "app_name asli tidak ditemukan"; exit 1; }
sed -i "s#<string name=\"app_name\">PPSSPP</string>#<string name=\"app_name\">$NEW_NAME</string>#" "$STR"

# 5. Teks info folder data di layar MemStick (kosmetik)
sed -i "s#Android/data/org.ppsspp.ppsspp/files#Android/data/$NEW_ID/files#" "$SRC/UI/MemStickScreen.cpp"

echo "OK: dasar PPSSPP Openvpn diterapkan (applicationId=$NEW_ID, nama=$NEW_NAME)"
