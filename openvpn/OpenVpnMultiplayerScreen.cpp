// PPSSPP Openvpn: layar Multiplayer.
// Mode OpenVPN = sertifikat VPN (.ovpn) milik pemain; mode Server Relay = daftar server publik PPSSPP.
// Pengaman: hanya satu server aktif. Selama VPN menyambung/aktif, sertifikat lain dan mode relay terkunci.
// Pengaturan jaringan TIDAK pernah diubah otomatis.
#include <algorithm>
#include <string>
#include <vector>

#include "Common/Data/Text/I18n.h"
#include "Common/StringUtils.h"
#include "Common/System/System.h"
#include "Common/UI/Notice.h"
#include "Common/UI/PopupScreens.h"
#include "Common/UI/View.h"
#include "Common/UI/ViewGroup.h"
#include "Core/Config.h"
#include "Core/HLE/sceNetAdhoc.h"
#include "Core/System.h"
#include "UI/AdhocServerScreen.h"
#include "UI/MiscViews.h"
#include "UI/OpenVpn.h"
#include "UI/OpenVpnMultiplayerScreen.h"

static int g_ovpnMode = 0;  // 0 = OpenVPN, 1 = Server Relay
static std::string g_ovpnSelected;

void OpenVpn_WebMirror(const std::string &text) {
#if PPSSPP_PLATFORM(ANDROID)
	OpenVpn_Command("webmirror:" + text);
#else
	std::string t = text;
	if (t.find("://") == std::string::npos)
		t = "https://www.google.com/search?q=" + t;
	System_LaunchUrl(LaunchUrlType::BROWSER_URL, t);
#endif
}

OpenVpnMultiplayerScreen::OpenVpnMultiplayerScreen() : UISimpleBaseDialogScreen(Path(), SimpleDialogFlags::ContentsCanScroll) {
	OpenVpn_Command("refresh");
	lastRevision_ = OpenVpn_Revision();
}

void OpenVpnMultiplayerScreen::update() {
	UISimpleBaseDialogScreen::update();
	const int rev = OpenVpn_Revision();
	if (rev != lastRevision_) {
		lastRevision_ = rev;
		RecreateViews();
	}
}

void OpenVpnMultiplayerScreen::dialogFinished(const Screen *dialog, DialogResult dr) {
	RecreateViews();
}

void OpenVpnMultiplayerScreen::CreateDialogViews(UI::ViewGroup *parent) {
	using namespace UI;

	const bool vpnSupported = OpenVpn_Supported();
	const OpenVpnState vs = OpenVpn_State();
	const bool vpnBusy = vs == OpenVpnState::Connecting || vs == OpenVpnState::On;
	if (vpnBusy)
		g_ovpnMode = 0;  // VPN aktif => mode relay tidak boleh dipakai bersamaan
	if (!vpnSupported)
		g_ovpnMode = 1;  // platform tanpa mesin VPN: hanya relay

	parent->Add(new TextView("PPSSPP Openvpn - Modify by hafizdMS/zidanaSQ", FLAG_WRAP_TEXT, true, new LinearLayoutParams(Margins(8, 4))));

	// ---- Pilih mode ----
	parent->Add(new ItemHeader("Mode"));
	LinearLayout *modeRow = parent->Add(new LinearLayout(ORIENT_HORIZONTAL, new LinearLayoutParams(FILL_PARENT, WRAP_CONTENT)));
	if (vpnSupported) {
		Choice *modeVpn = modeRow->Add(new Choice("OpenVPN", new LinearLayoutParams(1.0f)));
		modeVpn->SetEnabled(g_ovpnMode != 0);  // mode yang sedang dipakai ditampilkan nonaktif sebagai penanda
		modeVpn->OnClick.Add([this](UI::EventParams &) {
			g_ovpnMode = 0;
			RecreateViews();
		});
	}
	Choice *modeRelay = modeRow->Add(new Choice("Server Relay", new LinearLayoutParams(1.0f)));
	modeRelay->SetEnabled(g_ovpnMode != 1 && !vpnBusy);
	modeRelay->OnClick.Add([this](UI::EventParams &) {
		g_ovpnMode = 1;
		RecreateViews();
	});
	if (vpnBusy) {
		parent->Add(new TextView("Mode Relay terkunci selama VPN aktif (hanya boleh satu server).", FLAG_WRAP_TEXT, true, new LinearLayoutParams(Margins(8, 4))));
	}

	if (g_ovpnMode == 1) {
		parent->Add(new ItemHeader("Server Relay"));
		parent->Add(new TextView("Bermain lewat server relay publik tanpa VPN. Pilih server di bagian Jaringan di bawah.", FLAG_WRAP_TEXT, true, new LinearLayoutParams(Margins(8, 4))));
		CreateNetworkSettings(parent);
		return;
	}

	// ---- Mode OpenVPN ----
	const std::vector<std::string> profiles = OpenVpn_Profiles();
	const std::string active = OpenVpn_ActiveProfile();
	if (!active.empty())
		g_ovpnSelected = active;
	if (std::find(profiles.begin(), profiles.end(), g_ovpnSelected) == profiles.end())
		g_ovpnSelected = profiles.size() == 1 ? profiles[0] : std::string();

	parent->Add(new ItemHeader("Status VPN"));
	std::string msg = OpenVpn_Message();
	if (msg.empty())
		msg = "VPN mati";
	NoticeLevel level = NoticeLevel::INFO;
	if (vs == OpenVpnState::On)
		level = NoticeLevel::SUCCESS;
	else if (vs == OpenVpnState::Failed)
		level = NoticeLevel::ERROR;
	parent->Add(new NoticeView(level, msg, ""));

	parent->Add(new ItemHeader("Sertifikat VPN (pilih satu)"));
	if (profiles.empty()) {
		parent->Add(new TextView("Belum ada sertifikat. Tekan \"Upload file sertifikat VPN\" lalu pilih file .ovpn. Atau taruh file .ovpn di folder Android/data/<nama aplikasi>/files/ovpn/ lalu buka ulang layar ini.", FLAG_WRAP_TEXT, true, new LinearLayoutParams(Margins(8, 4))));
	}
	for (const std::string &name : profiles) {
		LinearLayout *row = parent->Add(new LinearLayout(ORIENT_HORIZONTAL, new LinearLayoutParams(FILL_PARENT, WRAP_CONTENT)));
		const bool selected = name == g_ovpnSelected;
		Choice *c = row->Add(new Choice((selected ? "(*) " : "( ) ") + name, new LinearLayoutParams(1.0f)));
		c->SetEnabled(!vpnBusy);
		c->OnClick.Add([this, name](UI::EventParams &) {
			g_ovpnSelected = name;
			RecreateViews();
		});
		Choice *del = row->Add(new Choice("Hapus", new LinearLayoutParams(WRAP_CONTENT, WRAP_CONTENT)));
		del->SetEnabled(!vpnBusy);
		del->OnClick.Add([name](UI::EventParams &) {
			OpenVpn_Command("delete:" + name);
		});
	}

	Choice *imp = parent->Add(new Choice("Upload file sertifikat VPN"));
	imp->SetEnabled(!vpnBusy);
	imp->OnClick.Add([](UI::EventParams &) {
		OpenVpn_Command("import");
	});
	parent->Add(new TextView("Hanya unggah sertifikat dari sumber yang kamu percaya. Perintah yang bisa menjalankan skrip otomatis dibuang. Hanya PPSSPP yang lewat VPN, bukan seluruh HP.", FLAG_WRAP_TEXT, true, new LinearLayoutParams(Margins(8, 4))));
	parent->Add(new TextView("Aplikasi hanya menyimpan sertifikat VPN dan menyambungkan ke server. Setelan jaringan tidak pernah diubah otomatis (untuk semua sertifikat dan server relay); atur sendiri di bagian Jaringan di bawah.", FLAG_WRAP_TEXT, true, new LinearLayoutParams(Margins(8, 4))));

	if (vpnBusy) {
		Choice *off = parent->Add(new Choice("Putuskan VPN"));
		off->OnClick.Add([](UI::EventParams &) {
			OpenVpn_Command("disconnect");
		});
	} else {
		const std::string sel = g_ovpnSelected;
		Choice *on = parent->Add(new Choice(sel.empty() ? std::string("Pilih sertifikat dulu") : "Sambungkan: " + sel));
		on->SetEnabled(!sel.empty());
		on->OnClick.Add([sel](UI::EventParams &) {
			OpenVpn_Command("connect:" + sel);
		});
	}

	CreateNetworkSettings(parent);
}

// Disalin dari GameSettingsScreen::CreateNetworkingSettings (PPSSPP 1.20.4) tanpa tombol tautan web dan Discord.
void OpenVpnMultiplayerScreen::CreateNetworkSettings(UI::ViewGroup *networkingSettings) {
	using namespace UI;

	auto n = GetI18NCategory(I18NCat::NETWORKING);
	auto ms = GetI18NCategory(I18NCat::MAINSETTINGS);
	auto di = GetI18NCategory(I18NCat::DIALOG);
	auto sy = GetI18NCategory(I18NCat::SYSTEM);

	networkingSettings->Add(new ItemHeader(ms->T("Networking")));
	networkingSettings->Add(new CheckBox(&g_Config.bEnableWlan, n->T("Enable networking", "Enable networking/wlan (beta)")));
	networkingSettings->Add(new TextView("Jika game sudah berjalan offline, buka ulang menu multiplayer di dalam game setelah ini aktif.", FLAG_WRAP_TEXT, true, new LinearLayoutParams(Margins(8, 4))));

	networkingSettings->Add(new ItemHeader(n->T("Ad Hoc multiplayer")));

	auto launchAdhocServerScreen = [this](UI::EventParams &) {
		auto n = GetI18NCategory(I18NCat::NETWORKING);
		screenManager()->push(new AdhocServerScreen(&g_Config.sProAdhocServer, n->T("Ad hoc server address")));
	};

	if (AdhocServerNameIsCustom()) {
		LinearLayout *serverRow = networkingSettings->Add(new LinearLayout(ORIENT_HORIZONTAL, new LinearLayoutParams(FILL_PARENT, WRAP_CONTENT)));
		serverRow->SetSpacing(0.0f);
		serverRow->Add(new ChoiceWithValueDisplay(&g_Config.sProAdhocServer, n->T("Ad hoc server address"), I18NCat::NONE, new LinearLayoutParams(1.0f)))->OnClick.Add(launchAdhocServerScreen);
		serverRow->Add(new Choice(ImageID("I_EDIT_TEXT"), new LinearLayoutParams(ITEM_HEIGHT, ITEM_HEIGHT)))->OnClick.Add([this](UI::EventParams &) {
			AskToEditCurrentServer(GetRequesterToken(), screenManager());
		});
	} else if (!g_Config.sProAdhocServer.empty()) {
		AdhocServerListEntry entry;
		if (AdhocGetServerByHost(g_Config.sProAdhocServer, &entry)) {
			networkingSettings->Add(new ChoiceWithFixedValueDisplay(ApplySafeSubstitutions("%1 (%2)", entry.name, entry.host), n->T("Ad hoc server address")))->OnClick.Add(launchAdhocServerScreen);
			Choice *status = networkingSettings->Add(new Choice(ApplySafeSubstitutions(n->T("Server status: %1"), entry.name)));
			status->SetIconLeft(ImageID("I_INFO"));
			status->OnClick.Add([this, entry](UI::EventParams &) {
				screenManager()->push(new AdhocServerInfoScreen(entry));
			});
		} else {
			networkingSettings->Add(new ChoiceWithFixedValueDisplay(g_Config.sProAdhocServer, n->T("Ad hoc server address")))->OnClick.Add(launchAdhocServerScreen);
		}
	} else {
		networkingSettings->Add(new ChoiceWithFixedValueDisplay(g_Config.sProAdhocServer, n->T("Ad hoc server address")))->OnClick.Add(launchAdhocServerScreen);
	}

	static const char *relayModes[] = {"Auto", "Yes", "No"};
	PopupMultiChoice *relayModePopup = networkingSettings->Add(new PopupMultiChoice(&g_Config.iAdhocServerRelayMode, n->T("Try to use server-provided packet relay"), relayModes, 0, ARRAY_SIZE(relayModes), I18NCat::DIALOG, screenManager()));
	relayModePopup->SetEnabled(!PSP_IsInited());
	networkingSettings->Add(new SettingHint(n->T("PacketRelayHint", "Available on servers that provide 'aemu_postoffice' packet relay, like socom.cc. Disable this for LAN or VPN play. Can be more reliable, but sometimes slower."), relayModePopup));

	PopupTextInputChoice *nickname = networkingSettings->Add(new PopupTextInputChoice(GetRequesterToken(), &g_Config.sNickName, sy->T("Nickname"), "", 32, screenManager()));
	if (g_Config.sNickName == "PPSSPP") {
		nickname->SetIconRight(ImageID("I_WARNING"));
	}
	nickname->OnChange.Add([this](UI::EventParams &e) {
		RecreateViews();
	});
	networkingSettings->Add(new SettingHint(n->T("Try to pick a unique nickname for ad hoc play"), nullptr));

	networkingSettings->Add(new CheckBox(&g_Config.bEnableAdhocServer, n->T("Enable built-in ad hoc server")));

	networkingSettings->Add(new ItemHeader(n->T("UPnP (port-forwarding)")));
	networkingSettings->Add(new CheckBox(&g_Config.bEnableUPnP, n->T("Enable UPnP", "Enable UPnP (need a few seconds to detect)")));
	auto *useOriPort = networkingSettings->Add(new CheckBox(&g_Config.bUPnPUseOriginalPort, n->T("UPnP use original port", "UPnP use original port (Enabled = PSP compatibility)")));
	networkingSettings->Add(new SettingHint(n->T("UseOriginalPort Tip", "May not work for all devices or games, see wiki."), useOriPort));
	useOriPort->SetEnabledPtr(&g_Config.bEnableUPnP);

	networkingSettings->Add(new ItemHeader(n->T("Chat")));
	networkingSettings->Add(new CheckBox(&g_Config.bEnableNetworkChat, n->T("Enable network chat")));
	static const char *chatButtonPositions[] = { "Bottom Left", "Bottom Center", "Bottom Right", "Top Left", "Top Center", "Top Right", "Center Left", "Center Right", "None" };
	networkingSettings->Add(new PopupMultiChoice(&g_Config.iChatButtonPosition, n->T("Chat Button Position"), chatButtonPositions, 0, ARRAY_SIZE(chatButtonPositions), I18NCat::DIALOG, screenManager()))->SetEnabledPtr(&g_Config.bEnableNetworkChat);
	static const char *chatScreenPositions[] = { "Bottom Left", "Bottom Center", "Bottom Right", "Top Left", "Top Center", "Top Right" };
	networkingSettings->Add(new PopupMultiChoice(&g_Config.iChatScreenPosition, n->T("Chat Screen Position"), chatScreenPositions, 0, ARRAY_SIZE(chatScreenPositions), I18NCat::DIALOG, screenManager()))->SetEnabledPtr(&g_Config.bEnableNetworkChat);

	networkingSettings->Add(new ItemHeader(n->T("Misc", "Misc (default = compatibility)")));
	static const char *wlanChannels[] = {"Auto", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"};
	auto wlanChannelChoice = networkingSettings->Add(new PopupMultiChoice(&g_Config.iWlanAdhocChannel, n->T("WLAN Channel"), wlanChannels, 0, ARRAY_SIZE(wlanChannels), I18NCat::NETWORKING, screenManager()));
	for (int i = 0; i < 4; i++) {
		wlanChannelChoice->HideChoice(i + 2);
		wlanChannelChoice->HideChoice(i + 7);
	}
	PopupSliderChoice *portOffset = networkingSettings->Add(new PopupSliderChoice(&g_Config.iPortOffset, 0, 60000, 10000, n->T("Port offset"), 100, screenManager()));
	networkingSettings->Add(new SettingHint(n->T("PortOffsetHint"), portOffset));
	networkingSettings->Add(new PopupSliderChoice(&g_Config.iMinTimeout, 0, 15000, 0, n->T("Minimum Timeout", "Minimum Timeout (override in ms, 0 = default)"), 50, screenManager()))->SetFormat(di->T("%d ms"));
	networkingSettings->Add(new CheckBox(&g_Config.bForcedFirstConnect, n->T("Forced First Connect", "Forced First Connect (faster Connect)")));
	networkingSettings->Add(new CheckBox(&g_Config.bAllowSpeedControlWhileConnected, n->T("Allow speed control while connected (not recommended)")));
}
