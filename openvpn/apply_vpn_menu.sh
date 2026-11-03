#!/usr/bin/env bash
# Bagian native: layar Multiplayer, tombol di menu utama + layar game, jembatan C++ <-> Java, dan kredit.
# Pakai: bash apply_vpn_menu.sh <folder ppsspp> <folder repo>
set -euo pipefail

PPSSPP="$(cd "${1:?Pakai: apply_vpn_menu.sh <ppsspp> <repo>}" && pwd)"
RV="$(cd "${2:?Pakai: apply_vpn_menu.sh <ppsspp> <repo>}" && pwd)"

for f in UI/MainScreen.cpp UI/GameScreen.cpp UI/MiscScreens.cpp android/jni/app-android.cpp CMakeLists.txt \
         android/src/org/ppsspp/ppsspp/PpssppActivity.java; do
  [ -f "$PPSSPP/$f" ] || { echo "ERROR: $f tidak ada"; exit 1; }
done

cp "$RV/openvpn/OpenVpn.h" "$RV/openvpn/OpenVpnMultiplayerScreen.h" "$RV/openvpn/OpenVpnMultiplayerScreen.cpp" "$PPSSPP/UI/"
echo "OK  file UI disalin"

python3 - "$PPSSPP" <<'PY'
import os, sys
root = sys.argv[1]

def patch(rel, edits, marker):
    p = os.path.join(root, rel)
    s = open(p, encoding="utf-8", newline="").read()
    if marker in s:
        print(f"OK  {rel} sudah dipatch"); return
    nl = "\r\n" if "\r\n" in s else "\n"
    for old, new in edits:
        old = old.replace("\n", nl); new = new.replace("\n", nl)
        assert s.count(old) == 1, f"{rel}: anchor tidak tunggal/tidak ada: {old[:70]!r} (n={s.count(old)})"
        s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8", newline="").write(s)
    print(f"OK  {rel} dipatch")

# ---- CMake + Android.mk: daftarkan file baru ----
patch("CMakeLists.txt", [
 ("\tUI/PauseScreen.cpp\n",
  "\tUI/PauseScreen.cpp\n\tUI/OpenVpnMultiplayerScreen.h\n\tUI/OpenVpnMultiplayerScreen.cpp  # OPENVPN-MOD\n"),
], "OPENVPN-MOD")

mk = os.path.join(root, "android/jni/Android.mk")
if os.path.exists(mk):
    patch("android/jni/Android.mk", [
     ("  $(SRC)/UI/PauseScreen.cpp \\\n",
      "  $(SRC)/UI/PauseScreen.cpp \\\n  $(SRC)/UI/OpenVpnMultiplayerScreen.cpp \\\n"),
    ], "OpenVpnMultiplayerScreen")

# ---- app-android.cpp: status VPN (diisi dari Java) + perintah ke Java ----
patch("android/jni/app-android.cpp", [
 ('#include "Core/Config.h"\n',
  '#include "Core/Config.h"\n#include <atomic>  // OPENVPN-MOD\n#include <mutex>\n#include <string>\n#include <vector>\n#include "UI/OpenVpn.h"\n'),
 ('// Android implementation of callbacks to the Java part of the app\n',
  '''// OPENVPN-MOD: status VPN tertanam (diisi dari Java lewat sendMessageFromJava).
static std::mutex g_ovpnMutex;
static std::string g_ovpnMessage;
static std::string g_ovpnActive;
static std::vector<std::pair<std::string, std::string>> g_ovpnProfiles;  // nama
static std::atomic<int> g_ovpnState{0};
static std::atomic<int> g_ovpnRevision{0};

OpenVpnState OpenVpn_State() {
	return (OpenVpnState)g_ovpnState.load();
}

int OpenVpn_Revision() {
	return g_ovpnRevision.load();
}

std::string OpenVpn_Message() {
	std::lock_guard<std::mutex> guard(g_ovpnMutex);
	return g_ovpnMessage;
}

std::string OpenVpn_ActiveProfile() {
	std::lock_guard<std::mutex> guard(g_ovpnMutex);
	return g_ovpnActive;
}

std::vector<std::string> OpenVpn_Profiles() {
	std::lock_guard<std::mutex> guard(g_ovpnMutex);
	std::vector<std::string> names;
	for (const auto &p : g_ovpnProfiles)
		names.push_back(p.first);
	return names;
}

void OpenVpn_Command(const std::string &cmd) {
	PushCommand("openvpn", cmd);
}

// Android implementation of callbacks to the Java part of the app
'''),
 ('\t} else if (msg == "sustained_perf_supported") {\n',
  '''\t} else if (msg == "openvpn_state") {
\t\tg_ovpnState = atoi(prm.c_str());
\t\tg_ovpnRevision++;
\t} else if (msg == "openvpn_msg") {
\t\t{
\t\t\tstd::lock_guard<std::mutex> guard(g_ovpnMutex);
\t\t\tg_ovpnMessage = prm;
\t\t}
\t\tg_ovpnRevision++;
\t} else if (msg == "openvpn_active") {
\t\t{
\t\t\tstd::lock_guard<std::mutex> guard(g_ovpnMutex);
\t\t\tg_ovpnActive = prm;
\t\t}
\t\tg_ovpnRevision++;
\t} else if (msg == "openvpn_profiles") {
\t\t{
\t\t\tstd::lock_guard<std::mutex> guard(g_ovpnMutex);
\t\t\tg_ovpnProfiles.clear();
\t\t\tsize_t start = 0;
\t\t\twhile (start <= prm.size() && !prm.empty()) {
\t\t\t\tsize_t end = prm.find('\\n', start);
\t\t\t\tif (end == std::string::npos)
\t\t\t\t\tend = prm.size();
\t\t\t\tif (end > start) {
\t\t\t\t\tstd::string line = prm.substr(start, end - start);
\t\t\t\t\tsize_t tab = line.find('\\t');
\t\t\t\t\tif (tab == std::string::npos)
\t\t\t\t\t\tg_ovpnProfiles.push_back({line, std::string()});
\t\t\t\t\telse
\t\t\t\t\t\tg_ovpnProfiles.push_back({line.substr(0, tab), line.substr(tab + 1)});
\t\t\t\t}
\t\t\t\tstart = end + 1;
\t\t\t}
\t\t}
\t\tg_ovpnRevision++;
\t} else if (msg == "sustained_perf_supported") {
'''),
], "OPENVPN-MOD")

# ---- PpssppActivity.java: terima perintah dari native ----
patch("android/src/org/ppsspp/ppsspp/PpssppActivity.java", [
 ('\t\t} else if (command.equals("copy_to_clipboard")) {\n',
  '''\t\t} else if (command.equals("openvpn")) {  // OPENVPN-MOD
\t\t\tOpenVpnControl.get(this).handleCommand(this, params);
\t\t\treturn true;
\t\t} else if (command.equals("copy_to_clipboard")) {
'''),
], "OPENVPN-MOD")

# ---- MainScreen.cpp: tombol Multiplayer ----
patch("UI/MainScreen.cpp", [
 ('#include "UI/RemoteISOScreen.h"\n',
  '#include "UI/RemoteISOScreen.h"\n#include "UI/OpenVpnMultiplayerScreen.h"  // OPENVPN-MOD\n'),
 ('''->OnClick.Handle(this, &MainScreen::OnCredits);

\tif (!portrait) {''',
  '''->OnClick.Handle(this, &MainScreen::OnCredits);

\t// OPENVPN-MOD: tombol Multiplayer (OpenVPN atau Server Relay).
\tparent->Add(new Choice("Multiplayer", portrait ? new LinearLayoutParams() : nullptr))->OnClick.Add([this](UI::EventParams &) {
\t\tscreenManager()->push(new OpenVpnMultiplayerScreen());
\t});

\tif (!portrait) {'''),
], "OPENVPN-MOD")

# ---- GameScreen.cpp (layar info game saat game ditahan): tombol Multiplayer ----
patch("UI/GameScreen.cpp", [
 ('#include "UI/CwCheatScreen.h"\n',
  '#include "UI/CwCheatScreen.h"\n#include "UI/OpenVpnMultiplayerScreen.h"  // OPENVPN-MOD\n'),
 ('\tif (g_Config.bEnableCheats) {\n\t\tauto pa = GetI18NCategory(I18NCat::PAUSE);\n\t\trightColumnItems->Add(new Choice(pa->T("Cheats")',
  '''\t// OPENVPN-MOD: tombol Multiplayer (tanpa alamat/IP di label).
\trightColumnItems->Add(new Choice("Multiplayer"))->OnClick.Add([this](UI::EventParams &) {
\t\tscreenManager()->push(new OpenVpnMultiplayerScreen());
\t});

\tif (g_Config.bEnableCheats) {
\t\tauto pa = GetI18NCategory(I18NCat::PAUSE);
\t\trightColumnItems->Add(new Choice(pa->T("Cheats")'''),
], "OPENVPN-MOD")

# ---- MiscScreens.cpp (layar Credits): "Modify by" ----
patch("UI/MiscScreens.cpp", [
 ('''\tdc.DrawText(temp, bounds.centerX(), startY + 70, textColor, ALIGN_CENTER);
\tdc.DrawText(cr->T_cstr("license", "Free Software under GPL 2.0+"), bounds.centerX(), startY + 110, textColor, ALIGN_CENTER);

\tdc.DrawText("www.ppsspp.org", bounds.centerX(), startY + 160, textColor, ALIGN_CENTER);
''',
  '''\tdc.DrawText(temp, bounds.centerX(), startY + 70, textColor, ALIGN_CENTER);
\tdc.DrawText("Modify by hafizdMS/zidanaSQ", bounds.centerX(), startY + 95, textColor, ALIGN_CENTER);  // OPENVPN-MOD
\tdc.DrawText(cr->T_cstr("license", "Free Software under GPL 2.0+"), bounds.centerX(), startY + 125, textColor, ALIGN_CENTER);

\tdc.DrawText("www.ppsspp.org", bounds.centerX(), startY + 165, textColor, ALIGN_CENTER);
'''),
], "hafizdMS/zidanaSQ")
PY
echo "OK: layar Multiplayer + jembatan native + kredit terpasang."
