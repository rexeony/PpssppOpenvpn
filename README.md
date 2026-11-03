# PPSSPP Openvpn

PPSSPP 1.20.4 + layar Multiplayer + Web Mirror. Modify by hafizdMS/zidanaSQ.
Dibangun lewat GitHub Actions: tab Actions -> "Build PPSSPP Openvpn (APK ARM64)" -> Run workflow.

## Multiplayer
Tombol **Multiplayer** ada di menu utama, layar game (saat game ditahan), dan pause screen. Dua mode, hanya satu yang aktif:

1. **OpenVPN** - unggah file sertifikat VPN (.ovpn) lewat "Upload file sertifikat VPN", atau taruh di
   `Android/data/<package id>/files/ovpn/`. Tidak ada sertifikat yang ditanam di APK. Perintah yang bisa menjalankan skrip
   dibuang, dan hanya PPSSPP yang lewat VPN.
2. **Server Relay** - pilih server publik dari daftar bawaan PPSSPP.

Kedua mode memuat pengaturan Jaringan bawaan PPSSPP (terhubung ke config yang sama, jadi selalu sinkron).
Aplikasi hanya menyimpan sertifikat VPN dan menyambungkan ke server. Setelan jaringan TIDAK pernah diubah otomatis,
untuk semua sertifikat maupun server relay; atur sendiri.

## Pause screen
- Tab **Web Mirror**: ketik link atau kata kunci -> **Buka** menampilkan halaman sebagai pop-up (WebView).
- Tombol **Pemain relay**: pemain di semua game pada server relay yang sedang dipilih.

## Struktur
`apply_base.sh` -> `apply_vpn_engine.sh` -> `openvpn/apply_vpn_ui.sh` -> `openvpn/apply_vpn_menu.sh` (lihat `.github/workflows/openvpn_apk.yml`).
