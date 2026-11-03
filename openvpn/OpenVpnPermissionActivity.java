// PPSSPP Openvpn: activity transparan untuk meminta izin VPN Android.
package org.ppsspp.ppsspp;

import android.app.Activity;
import android.content.Intent;
import android.net.VpnService;
import android.os.Bundle;

public class OpenVpnPermissionActivity extends Activity {
	private static final int REQ_VPN = 4711;

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		Intent i = VpnService.prepare(this);
		if (i == null) {
			OpenVpnControl.get(this).startNow(getApplicationContext());
			finish();
		} else {
			startActivityForResult(i, REQ_VPN);
		}
	}

	@Override
	protected void onActivityResult(int requestCode, int resultCode, Intent data) {
		super.onActivityResult(requestCode, resultCode, data);
		if (requestCode == REQ_VPN) {
			if (resultCode == RESULT_OK) {
				OpenVpnControl.get(this).startNow(getApplicationContext());
			} else {
				OpenVpnControl.get(this).onPermissionDenied();
			}
		}
		finish();
	}
}
