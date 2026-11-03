// PPSSPP Openvpn: popup web mirror. Ketik link atau kata kunci, halaman tampil seperti browser di atas game.
package org.ppsspp.ppsspp;

import android.app.Activity;
import android.app.Dialog;
import android.graphics.Color;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.Toast;

import java.net.URLEncoder;
import java.util.Locale;

final class WebMirrorDialog {
	private static final String SEARCH_URL = "https://www.google.com/search?q=";

	private WebMirrorDialog() {}

	/**
	 * Link lengkap -> dipakai apa adanya (hanya http/https).
	 * Mirip domain ("youtube.com", "www.situs.id/path") -> ditambah https://.
	 * Selain itu dianggap kata kunci -> hasil pencarian. Null bila kosong atau skema tidak didukung.
	 */
	static String normalize(String raw) {
		String t = raw == null ? "" : raw.trim();
		if (t.isEmpty())
			return null;
		String lower = t.toLowerCase(Locale.ROOT);
		if (lower.matches("^[a-z][a-z0-9+.-]*://.*")) {
			return (lower.startsWith("http://") || lower.startsWith("https://")) ? t : null;
		}
		if (!t.contains(" ") && t.contains(".") && !t.startsWith(".") && !t.endsWith(".") && !lower.startsWith("javascript:")) {
			return "https://" + t;
		}
		try {
			return SEARCH_URL + URLEncoder.encode(t, "UTF-8");
		} catch (Exception e) {
			return null;
		}
	}

	static void show(final Activity act, final String raw) {
		act.runOnUiThread(() -> {
			final String first = normalize(raw);
			if (first == null) {
				Toast.makeText(act, "Ketik link atau kata kunci yang valid", Toast.LENGTH_SHORT).show();
				return;
			}
			final Dialog dialog = new Dialog(act, android.R.style.Theme_DeviceDefault_NoActionBar);

			LinearLayout root = new LinearLayout(act);
			root.setOrientation(LinearLayout.VERTICAL);
			root.setBackgroundColor(Color.BLACK);

			LinearLayout bar = new LinearLayout(act);
			bar.setOrientation(LinearLayout.HORIZONTAL);
			bar.setGravity(Gravity.CENTER_VERTICAL);
			final EditText address = new EditText(act);
			address.setSingleLine(true);
			address.setText(first);
			address.setTextColor(Color.WHITE);
			address.setHint("Ketik link atau kata kunci");
			address.setHintTextColor(Color.GRAY);
			address.setImeOptions(EditorInfo.IME_ACTION_GO);
			bar.addView(address, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
			Button close = new Button(act);
			close.setText("Tutup");
			bar.addView(close, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
			root.addView(bar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

			final WebView web = new WebView(act);
			WebSettings s = web.getSettings();
			s.setJavaScriptEnabled(true);
			s.setDomStorageEnabled(true);
			s.setAllowFileAccess(false);
			s.setAllowContentAccess(false);
			s.setSupportMultipleWindows(false);
			web.setWebChromeClient(new WebChromeClient());
			web.setWebViewClient(new WebViewClient() {
				@Override
				public boolean shouldOverrideUrlLoading(WebView v, android.webkit.WebResourceRequest req) {
					String u = req.getUrl().toString().toLowerCase(Locale.ROOT);
					return !(u.startsWith("http://") || u.startsWith("https://"));  // selain web: diblokir
				}

				@Override
				public void onPageFinished(WebView v, String url) {
					if (!address.hasFocus())
						address.setText(url);
				}
			});
			root.addView(web, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

			address.setOnEditorActionListener((v, actionId, ev) -> {
				if (actionId == EditorInfo.IME_ACTION_GO || (ev != null && ev.getKeyCode() == KeyEvent.KEYCODE_ENTER)) {
					String u = normalize(address.getText().toString());
					if (u != null) {
						web.loadUrl(u);
						address.clearFocus();
					}
					return true;
				}
				return false;
			});
			close.setOnClickListener(v -> dialog.dismiss());
			dialog.setOnKeyListener((d, keyCode, ev) -> {
				if (keyCode == KeyEvent.KEYCODE_BACK && ev.getAction() == KeyEvent.ACTION_UP) {
					if (web.canGoBack()) web.goBack(); else dialog.dismiss();
					return true;
				}
				return false;
			});
			dialog.setOnDismissListener(d -> {
				web.stopLoading();
				root.removeView(web);
				web.destroy();
			});

			dialog.setContentView(root);
			dialog.setCanceledOnTouchOutside(false);
			if (dialog.getWindow() != null)
				dialog.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
			dialog.show();
			if (dialog.getWindow() != null) {
				DisplayMetrics dm = act.getResources().getDisplayMetrics();
				dialog.getWindow().setLayout((int) (dm.widthPixels * 0.96f), (int) (dm.heightPixels * 0.94f));
			}
			web.loadUrl(first);
		});
	}
}
