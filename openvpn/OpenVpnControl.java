// PPSSPP Openvpn: kontrol VPN tertanam (memakai mesin ics-openvpn).
// Pemain mengunggah file sertifikat VPN (.ovpn) sendiri. Tidak ada sertifikat yang ditanam di APK.
// Lisensi mengikuti PPSSPP (GPL 2.0+).
package org.ppsspp.ppsspp;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.net.VpnService;
import android.os.IBinder;
import android.os.RemoteException;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

import de.blinkt.openvpn.VpnProfile;
import de.blinkt.openvpn.core.ConfigParser;
import de.blinkt.openvpn.core.ConnectionStatus;
import de.blinkt.openvpn.core.IOpenVPNServiceInternal;
import de.blinkt.openvpn.core.OpenVPNService;
import de.blinkt.openvpn.core.ProfileManager;
import de.blinkt.openvpn.core.VPNLaunchHelper;
import de.blinkt.openvpn.core.VpnStatus;

public final class OpenVpnControl implements VpnStatus.StateListener {
	private static final String TAG = "OpenVpnControl";

	public static final int STATE_OFF = 0;
	public static final int STATE_CONNECTING = 1;
	public static final int STATE_ON = 2;
	public static final int STATE_ERROR = 3;

	private static final int MAX_BYTES = 256 * 1024;
	private static final int MAX_PROFILES = 20;

	// Direktif yang bisa menjalankan skrip/plugin, membuka management port, atau menyentuh file di perangkat.
	// Semuanya dibuang saat sertifikat diunggah.
	private static final Set<String> BLOCKED = new HashSet<>(Arrays.asList(
		"up", "down", "route-up", "route-pre-down", "ipchange", "client-connect", "client-disconnect",
		"learn-address", "auth-user-pass-verify", "tls-verify", "plugin", "script-security",
		"management", "management-client", "management-query-passwords", "management-hold",
		"management-forget-disconnect", "management-signal", "management-up-down", "management-log-cache",
		"setenv", "setenv-safe", "daemon", "log", "log-append", "syslog", "writepid", "chroot", "cd",
		"user", "group", "config", "dev-node", "tmp-dir", "status", "engine", "pkcs11-providers",
		"up-restart", "down-pre", "tls-export-cert", "echo", "cryptoapicert"));

	private static OpenVpnControl instance;

	private final File dir;
	private volatile int state = STATE_OFF;
	private volatile String message = "";
	private volatile String activeProfile = "";
	private volatile String pendingProfile = "";

	public static synchronized OpenVpnControl get(Context c) {
		if (instance == null) {
			instance = new OpenVpnControl(c.getApplicationContext());
			VpnStatus.addStateListener(instance);
		}
		return instance;
	}

	private OpenVpnControl(Context app) {
		dir = new File(app.getFilesDir(), "ovpn");
		//noinspection ResultOfMethodCallIgnored
		dir.mkdirs();
	}

	// ---------- helper nama & baca file ----------

	/** Nama profil yang aman dipakai sebagai nama file. */
	public static String safeName(String raw) {
		String n = raw == null ? "" : raw.trim();
		if (n.toLowerCase(Locale.ROOT).endsWith(".ovpn"))
			n = n.substring(0, n.length() - 5);
		n = n.replaceAll("[^A-Za-z0-9._ -]", "_").replaceAll("^[. ]+", "");
		if (n.length() > 40)
			n = n.substring(0, 40);
		return n.isEmpty() ? "profil" : n;
	}

	/** Baca stream maksimal MAX_BYTES. Null bila terlalu besar. */
	public static String readLimited(InputStream in) throws java.io.IOException {
		ByteArrayOutputStream out = new ByteArrayOutputStream();
		byte[] buf = new byte[8192];
		int n;
		while ((n = in.read(buf)) > 0) {
			out.write(buf, 0, n);
			if (out.size() > MAX_BYTES)
				return null;
		}
		return new String(out.toByteArray(), StandardCharsets.UTF_8);
	}

	private File fileFor(String name) {
		return new File(dir, safeName(name) + ".ovpn");
	}

	/** Buang direktif berbahaya. Isi blok inline (<ca>, <cert>, <key>, ...) dibiarkan utuh. */
	static String sanitize(String text) {
		StringBuilder sb = new StringBuilder();
		boolean inBlock = false;
		for (String line : text.replace("\r\n", "\n").replace('\r', '\n').split("\n", -1)) {
			String t = line.trim();
			if (inBlock) {
				sb.append(line).append('\n');
				if (t.startsWith("</")) inBlock = false;
				continue;
			}
			if (t.startsWith("<") && !t.startsWith("</")) {
				inBlock = true;
				sb.append(line).append('\n');
				continue;
			}
			String key = t.split("\\s+", 2)[0].toLowerCase(Locale.ROOT);
			if (key.startsWith("--")) key = key.substring(2);
			if (BLOCKED.contains(key)) continue;
			sb.append(line).append('\n');
		}
		return sb.toString();
	}

	// ---------- profil ----------

	/** Simpan sertifikat. Mengembalikan null bila sukses, atau pesan error. */
	public String saveProfile(String rawName, String text) {
		if (text == null || text.trim().isEmpty())
			return "File kosong";
		String name = safeName(rawName);
		if (!fileFor(name).exists() && listProfiles().length >= MAX_PROFILES)
			return "Jumlah sertifikat maksimal " + MAX_PROFILES;
		String clean = sanitize(text);
		try {
			ConfigParser cp = new ConfigParser();
			cp.parseConfig(new StringReader(clean));
			cp.convertProfile();  // validasi
		} catch (Exception e) {
			return "File sertifikat VPN tidak valid: " + e.getMessage();
		}
		try (FileOutputStream out = new FileOutputStream(fileFor(name))) {
			out.write(clean.getBytes(StandardCharsets.UTF_8));
		} catch (Exception e) {
			return "Gagal menyimpan sertifikat: " + e.getMessage();
		}
		pushProfiles();
		return null;
	}

	private String[] listProfiles() {
		File[] fs = dir.listFiles((d, n) -> n.endsWith(".ovpn"));
		if (fs == null) return new String[0];
		String[] names = new String[fs.length];
		for (int i = 0; i < fs.length; i++) {
			String n = fs[i].getName();
			names[i] = n.substring(0, n.length() - 5);
		}
		Arrays.sort(names, String.CASE_INSENSITIVE_ORDER);
		return names;
	}

	/** Impor otomatis semua *.ovpn yang ditaruh pemain di Android/data/<app>/files/ovpn/. */
	private void scanDropFolder(Context c) {
		File ext = c.getExternalFilesDir("ovpn");
		if (ext == null) return;
		File[] fs = ext.listFiles((d, n) -> n.toLowerCase(Locale.ROOT).endsWith(".ovpn"));
		if (fs == null) return;
		for (File f : fs) {
			if (fileFor(f.getName()).exists()) continue;
			try (FileInputStream in = new FileInputStream(f)) {
				String text = readLimited(in);
				String err = text == null ? "File terlalu besar" : saveProfile(f.getName(), text);
				if (err != null) report(f.getName() + ": " + err);
			} catch (Exception e) {
				report("Gagal membaca " + f.getName());
			}
		}
	}

	// ---------- perintah dari native ----------

	public void handleCommand(Context c, String cmd) {
		if (cmd.equals("refresh")) {
			scanDropFolder(c);
			pushAll();
		} else if (cmd.equals("import")) {
			Intent i = new Intent(c, OpenVpnImportActivity.class);
			if (!(c instanceof Activity))
				i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			c.startActivity(i);
		} else if (cmd.startsWith("delete:")) {
			String name = safeName(cmd.substring(7));
			if (state == STATE_CONNECTING || state == STATE_ON) {
				report("Putuskan VPN dulu sebelum menghapus sertifikat");
			} else if (fileFor(name).delete()) {
				report("Sertifikat '" + name + "' dihapus");
				pushProfiles();
			}
		} else if (cmd.startsWith("connect:")) {
			connect(c, cmd.substring(8));
		} else if (cmd.equals("disconnect")) {
			disable(c);
		} else if (cmd.startsWith("webmirror:")) {
			if (c instanceof Activity)
				WebMirrorDialog.show((Activity) c, cmd.substring(10));
		}
	}

	/** Dipanggil activity unggah untuk menampilkan hasil. */
	public void report(String msg) {
		message = msg;
		pushMessage();
	}

	// ---------- koneksi ----------

	private void connect(Context c, String raw) {
		if (state == STATE_CONNECTING || state == STATE_ON) {
			report("Sudah ada VPN aktif (hanya boleh satu server)");
			return;
		}
		String name = safeName(raw);
		if (!fileFor(name).exists()) {
			report("Sertifikat tidak ditemukan");
			return;
		}
		Context app = c.getApplicationContext();
		pendingProfile = name;
		activeProfile = name;
		set(STATE_CONNECTING, "Menyambung ke " + name + "...");
		Intent need = VpnService.prepare(app);
		if (need == null) {
			startNow(app);
		} else {
			// Izin VPN Android belum diberikan: minta lewat activity transparan.
			Intent i = new Intent(app, OpenVpnPermissionActivity.class);
			i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			app.startActivity(i);
		}
	}

	void onPermissionDenied() {
		activeProfile = "";
		set(STATE_OFF, "Izin VPN ditolak");
	}

	void startNow(Context app) {
		try {
			VpnProfile vp = buildProfile(app, pendingProfile);
			ProfileManager.setTemporaryProfile(app, vp);
			VPNLaunchHelper.startOpenVpn(vp, app, "PPSSPP Openvpn", true);
		} catch (Exception e) {
			Log.e(TAG, "Gagal memulai VPN", e);
			activeProfile = "";
			set(STATE_ERROR, "Gagal: " + e.getMessage());
		}
	}

	private VpnProfile buildProfile(Context app, String name) throws Exception {
		ConfigParser cp = new ConfigParser();
		String text;
		try (InputStream in = new FileInputStream(fileFor(name))) {
			text = readLimited(in);
		}
		if (text == null) throw new Exception("file terlalu besar");
		cp.parseConfig(new StringReader(sanitize(text)));
		VpnProfile vp = cp.convertProfile();
		vp.mName = name;

		// Hanya aplikasi ini yang lewat VPN, bukan seluruh HP.
		vp.mAllowedAppsVpn.clear();
		vp.mAllowedAppsVpn.add(app.getPackageName());
		vp.mAllowedAppsVpnAreDisallowed = false;

		return vp;
	}

	public void disable(Context c) {
		final Context app = c.getApplicationContext();
		Intent i = new Intent(app, OpenVPNService.class);
		i.setAction(OpenVPNService.START_SERVICE);
		ServiceConnection conn = new ServiceConnection() {
			@Override
			public void onServiceConnected(ComponentName name, IBinder binder) {
				try {
					IOpenVPNServiceInternal.Stub.asInterface(binder).stopVPN(false);
				} catch (RemoteException e) {
					Log.e(TAG, "stopVPN gagal", e);
				}
				app.unbindService(this);
			}
			@Override
			public void onServiceDisconnected(ComponentName name) {}
		};
		if (!app.bindService(i, conn, Context.BIND_AUTO_CREATE)) {
			activeProfile = "";
			set(STATE_OFF, "VPN mati");
		}
	}

	@Override
	public void updateState(String s, String logmessage, int resId, ConnectionStatus level, Intent intent) {
		switch (level) {
		case LEVEL_CONNECTED:
			set(STATE_ON, "VPN aktif: " + activeProfile); break;
		case LEVEL_NOTCONNECTED:
			// Jangan menimpa pesan error/izin ditolak dengan "mati" generik.
			if (state != STATE_ERROR) {
				activeProfile = "";
				set(STATE_OFF, "VPN mati");
			}
			break;
		case LEVEL_AUTH_FAILED:
			set(STATE_ERROR, "Autentikasi gagal"); break;
		case LEVEL_WAITING_FOR_USER_INPUT:
			set(STATE_ERROR, "Sertifikat ini butuh username/password (belum didukung)"); break;
		case LEVEL_NONETWORK:
			set(STATE_CONNECTING, "Menunggu jaringan..."); break;
		case LEVEL_VPNPAUSED:
		case LEVEL_START:
		case LEVEL_CONNECTING_SERVER_REPLIED:
		case LEVEL_CONNECTING_NO_SERVER_REPLY_YET:
			set(STATE_CONNECTING, "Menyambung ke " + activeProfile + "..."); break;
		default:
			break;
		}
	}

	@Override
	public void setConnectedVPN(String uuid) {}

	// ---------- sinkronisasi ke sisi native ----------

	private void set(int st, String text) {
		state = st;
		message = text;
		pushAll();
	}

	private void send(String key, String value) {
		try {
			NativeApp.sendMessageFromJava(key, value);
		} catch (Throwable t) {
			Log.w(TAG, "Native belum siap: " + t);
		}
	}

	private void pushMessage() { send("openvpn_msg", message); }

	/** Satu baris per sertifikat (nama). */
	private void pushProfiles() {
		StringBuilder sb = new StringBuilder();
		for (String n : listProfiles()) {
			if (sb.length() > 0) sb.append('\n');
			sb.append(n);
		}
		send("openvpn_profiles", sb.toString());
	}

	private void pushAll() {
		send("openvpn_active", activeProfile);
		pushProfiles();
		pushMessage();
		send("openvpn_state", String.valueOf(state));
	}
}
