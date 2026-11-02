package org.goosebox.revolutshare;

import android.app.Notification;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public class RevolutListener extends NotificationListenerService {
    private static final String REVOLUT = "com.revolut.revolut";
    private static final Object LOCK = new Object();

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        if (!REVOLUT.equals(sbn.getPackageName())) {
            return;
        }
        Bundle extras = sbn.getNotification().extras;
        CharSequence title = extras.getCharSequence(Notification.EXTRA_TITLE);
        CharSequence big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT);
        CharSequence text = big != null ? big : extras.getCharSequence(Notification.EXTRA_TEXT);
        if (title == null || text == null || !text.toString().contains("You spent")) {
            return;
        }

        String date = new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(new Date(sbn.getPostTime()));
        try {
            JSONObject item = new JSONObject()
                    .put("id", date + "|" + title + "|" + text)
                    .put("title", title.toString())
                    .put("text", text.toString())
                    .put("date", date);
            enqueue(this, item);
        } catch (JSONException e) {
            return;
        }
        Context app = getApplicationContext();
        new Thread(() -> flush(app)).start();
    }

    static int pending(Context context) {
        return queue(context).length();
    }

    private static JSONArray queue(Context context) {
        try {
            return new JSONArray(SettingsActivity.prefs(context).getString("queue", "[]"));
        } catch (JSONException e) {
            return new JSONArray();
        }
    }

    private static void enqueue(Context context, JSONObject item) {
        synchronized (LOCK) {
            JSONArray items = queue(context);
            items.put(item);
            save(context, items);
        }
    }

    private static void save(Context context, JSONArray items) {
        SharedPreferences prefs = SettingsActivity.prefs(context);
        prefs.edit().putString("queue", items.toString()).apply();
    }

    // Unsent items stay queued until the server is reachable, for example after WireGuard reconnects.
    static void flush(Context context) {
        synchronized (LOCK) {
            JSONArray items = queue(context);
            JSONArray left = new JSONArray();
            boolean offline = false;
            for (int i = 0; i < items.length(); i++) {
                JSONObject item = items.optJSONObject(i);
                if (item == null) {
                    continue;
                }
                if (offline) {
                    left.put(item);
                    continue;
                }
                try {
                    byte[] body = item.toString().getBytes(StandardCharsets.UTF_8);
                    Api.post(context, "/notify", "application/json", body);
                } catch (IOException e) {
                    offline = true;
                    left.put(item);
                } catch (Api.Rejected e) {
                    left.put(item);
                }
            }
            save(context, left);
        }
    }
}
