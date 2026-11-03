#!/usr/bin/env bash
# Bagian Java: kontrol VPN tertanam, izin VPN, unggah sertifikat VPN, dan popup web mirror.
# Tidak ada sertifikat yang ditanam di APK; pemain mengunggah sendiri lewat layar Multiplayer.
# Pakai: bash apply_vpn_ui.sh <folder ppsspp> <folder ics-openvpn> <folder repo>
set -euo pipefail

PPSSPP="$(cd "${1:?Pakai: apply_vpn_ui.sh <ppsspp> <ics> <repo>}" && pwd)"
RV="$(cd "${3:?Pakai: apply_vpn_ui.sh <ppsspp> <ics> <repo>}" && pwd)"
HERE="$RV/openvpn"

JAVA_DIR="$PPSSPP/android/src/org/ppsspp/ppsspp"
MANIFEST="$PPSSPP/android/AndroidManifest.xml"

[ -d "$JAVA_DIR" ] || { echo "ERROR: $JAVA_DIR tidak ada"; exit 1; }
[ -f "$MANIFEST" ] || { echo "ERROR: $MANIFEST tidak ada"; exit 1; }

cp "$HERE/OpenVpnControl.java" "$HERE/OpenVpnPermissionActivity.java" "$HERE/OpenVpnImportActivity.java" "$HERE/WebMirrorDialog.java" "$JAVA_DIR/"
echo "OK  class Java disalin"

python3 - "$MANIFEST" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8", newline="").read()
if "OpenVpnPermissionActivity" in s:
    print("OK  manifest sudah dipatch"); sys.exit(0)
act = ('\n\t\t<!-- OPENVPN-MOD -->\n'
       '\t\t<activity android:name="org.ppsspp.ppsspp.OpenVpnPermissionActivity"\n'
       '\t\t\tandroid:exported="false"\n'
       '\t\t\tandroid:theme="@android:style/Theme.Translucent.NoTitleBar" />\n'
       '\t\t<activity android:name="org.ppsspp.ppsspp.OpenVpnImportActivity"\n'
       '\t\t\tandroid:exported="false"\n'
       '\t\t\tandroid:theme="@android:style/Theme.Translucent.NoTitleBar" />\n')
assert s.count("</application>") == 1, "tag </application> tidak tunggal"
s = s.replace("</application>", act + "\t</application>", 1)
open(p, "w", encoding="utf-8", newline="").write(s)
print("OK  manifest dipatch (izin VPN + unggah sertifikat)")
PY
echo "OK: bagian Java selesai."
