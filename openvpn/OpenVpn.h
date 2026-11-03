// PPSSPP Openvpn: antarmuka status/aksi VPN tertanam untuk UI native.
// Di Android diimplementasikan di android/jni/app-android.cpp; platform lain berupa stub.
#pragma once

#include <string>
#include <vector>

#include "ppsspp_config.h"

enum class OpenVpnState {
	Off = 0,
	Connecting = 1,
	On = 2,
	Failed = 3,
};

#if PPSSPP_PLATFORM(ANDROID)
OpenVpnState OpenVpn_State();
int OpenVpn_Revision();                              // naik setiap ada perubahan (status/pesan/sertifikat)
std::string OpenVpn_Message();
std::string OpenVpn_ActiveProfile();                 // kosong bila VPN mati
std::vector<std::string> OpenVpn_Profiles();
// "refresh", "import", "delete:<nama>", "connect:<nama>", "disconnect", "webmirror:<teks>"
void OpenVpn_Command(const std::string &cmd);
inline bool OpenVpn_Supported() { return true; }
#else
inline OpenVpnState OpenVpn_State() { return OpenVpnState::Off; }
inline int OpenVpn_Revision() { return 0; }
inline std::string OpenVpn_Message() { return std::string(); }
inline std::string OpenVpn_ActiveProfile() { return std::string(); }
inline std::vector<std::string> OpenVpn_Profiles() { return {}; }
inline void OpenVpn_Command(const std::string &) {}
inline bool OpenVpn_Supported() { return false; }
#endif

// Tampilkan popup web mirror untuk link/kata kunci (Android: WebView; platform lain: browser sistem).
void OpenVpn_WebMirror(const std::string &text);
