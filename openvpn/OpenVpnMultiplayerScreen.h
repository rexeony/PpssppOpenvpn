// PPSSPP Openvpn: layar Multiplayer (OpenVPN atau Server Relay). Dipakai dari menu utama, layar game, dan pause screen.
#pragma once

#include <string>

#include "UI/SimpleDialogScreen.h"

class OpenVpnMultiplayerScreen : public UISimpleBaseDialogScreen {
public:
	OpenVpnMultiplayerScreen();

	void update() override;
	void dialogFinished(const Screen *dialog, DialogResult dr) override;
	const char *tag() const override { return "OpenVpnMultiplayer"; }

protected:
	std::string_view GetTitle() const override { return "Multiplayer"; }
	void CreateDialogViews(UI::ViewGroup *parent) override;

private:
	// Salinan pengaturan Jaringan bawaan PPSSPP. Semua terhubung ke g_Config yang sama,
	// jadi selalu sinkron dengan Pengaturan > Jaringan.
	void CreateNetworkSettings(UI::ViewGroup *parent);

	int lastRevision_ = 0;
};
