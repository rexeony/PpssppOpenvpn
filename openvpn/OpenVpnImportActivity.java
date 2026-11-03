// PPSSPP Openvpn: activity transparan untuk memilih file sertifikat VPN (.ovpn) dan menyimpannya.
package org.ppsspp.ppsspp;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;

import java.io.InputStream;

public class OpenVpnImportActivity extends Activity {
	private static final int REQ_PICK = 4712;

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
		i.addCategory(Intent.CATEGORY_OPENABLE);
		i.setType("*/*");
		startActivityForResult(i, REQ_PICK);
	}

	@Override
	protected void onActivityResult(int requestCode, int resultCode, Intent data) {
		super.onActivityResult(requestCode, resultCode, data);
		OpenVpnControl vpn = OpenVpnControl.get(this);
		if (requestCode == REQ_PICK && resultCode == RESULT_OK && data != null && data.getData() != null) {
			Uri uri = data.getData();
			String result;
			try (InputStream in = getContentResolver().openInputStream(uri)) {
				String text = in == null ? null : OpenVpnControl.readLimited(in);
				if (text == null) {
					result = "File terlalu besar atau tidak bisa dibaca";
				} else {
					String name = displayName(uri);
					String err = vpn.saveProfile(name, text);
					result = err == null ? "Sertifikat VPN '" + OpenVpnControl.safeName(name) + "' ditambahkan" : err;
				}
			} catch (Exception e) {
				result = "Gagal membaca file: " + e.getMessage();
			}
			vpn.report(result);
		}
		finish();
	}

	private String displayName(Uri uri) {
		try (Cursor c = getContentResolver().query(uri, null, null, null, null)) {
			if (c != null && c.moveToFirst()) {
				int idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME);
				if (idx >= 0) return c.getString(idx);
			}
		} catch (Exception ignored) {}
		return "profil";
	}
}
