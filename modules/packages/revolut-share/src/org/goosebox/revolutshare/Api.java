package org.goosebox.revolutshare;

import android.content.Context;
import android.content.SharedPreferences;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import org.json.JSONException;
import org.json.JSONObject;

final class Api {
    static final class Rejected extends Exception {
        Rejected(String message) {
            super(message);
        }
    }

    private Api() {}

    static String base(Context context) {
        SharedPreferences prefs = SettingsActivity.prefs(context);
        String url = prefs.getString("url", SettingsActivity.DEFAULT_URL);
        return url.replaceAll("/+$", "").replaceAll("/import$", "");
    }

    static String token(Context context) {
        return SettingsActivity.prefs(context).getString("token", "");
    }

    static JSONObject post(Context context, String path, String type, byte[] body)
            throws IOException, Rejected {
        HttpURLConnection conn = (HttpURLConnection) new URL(base(context) + path).openConnection();
        conn.setConnectTimeout(10000);
        conn.setReadTimeout(120000);
        conn.setDoOutput(true);
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Authorization", "Bearer " + token(context));
        conn.setRequestProperty("Content-Type", type);
        try (OutputStream out = conn.getOutputStream()) {
            out.write(body);
        }

        int status = conn.getResponseCode();
        InputStream stream = status < 400 ? conn.getInputStream() : conn.getErrorStream();
        String text = new String(readAll(stream), StandardCharsets.UTF_8);
        try {
            JSONObject json = new JSONObject(text);
            if (status >= 400) {
                throw new Rejected(json.optString("error", "HTTP " + status));
            }
            return json;
        } catch (JSONException e) {
            throw new Rejected("HTTP " + status);
        }
    }

    static byte[] readAll(InputStream stream) throws IOException {
        try (InputStream in = stream) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            for (int n; (n = in.read(buffer)) > 0; ) {
                out.write(buffer, 0, n);
            }
            return out.toByteArray();
        }
    }
}
