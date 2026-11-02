package org.goosebox.revolutshare;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Toast;
import java.util.Iterator;
import org.json.JSONObject;

public class ShareActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Uri uri = fileUri(getIntent());

        if (Api.token(this).isEmpty()) {
            done("Set the token first");
            startActivity(new Intent(this, SettingsActivity.class));
            return;
        }
        if (uri == null) {
            done("No file received");
            return;
        }

        Toast.makeText(this, "Sending to Actual...", Toast.LENGTH_SHORT).show();
        new Thread(() -> {
            String message;
            try {
                byte[] csv = Api.readAll(getContentResolver().openInputStream(uri));
                message = summary(Api.post(this, "/import", "text/csv", csv));
            } catch (Exception e) {
                message = "Import failed: " + e.getMessage();
            }
            String result = message;
            runOnUiThread(() -> done(result));
        }).start();
    }

    @SuppressWarnings("deprecation")
    private static Uri fileUri(Intent intent) {
        if (Intent.ACTION_SEND.equals(intent.getAction())) {
            return intent.getParcelableExtra(Intent.EXTRA_STREAM);
        }
        return intent.getData();
    }

    private void done(String message) {
        Toast.makeText(getApplicationContext(), message, Toast.LENGTH_LONG).show();
        finish();
    }

    private static String summary(JSONObject json) throws Exception {
        StringBuilder text = new StringBuilder();
        JSONObject accounts = json.getJSONObject("accounts");
        for (Iterator<String> names = accounts.keys(); names.hasNext(); ) {
            String name = names.next();
            int added = accounts.getJSONObject(name).getInt("added");
            text.append(name).append(": ").append(added).append(" new\n");
        }
        if (text.length() == 0) {
            text.append("Nothing to import\n");
        }
        return text.append(json.getInt("skipped")).append(" pending skipped").toString();
    }
}
