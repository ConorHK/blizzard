package org.goosebox.revolutshare;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.provider.Settings;
import android.text.InputType;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

public class SettingsActivity extends Activity {
    static final String DEFAULT_URL = "http://10.100.0.1:8097";

    static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences("settings", MODE_PRIVATE);
    }

    private TextView status;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        SharedPreferences prefs = prefs(this);

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(48, 48, 48, 48);
        layout.setFitsSystemWindows(true);

        TextView help = new TextView(this);
        help.setText("Export a statement in Revolut, then open it with Send to Actual. "
                + "With notification access, card payments arrive as they happen.");
        layout.addView(help);

        EditText url = new EditText(this);
        url.setHint("Server URL");
        url.setText(Api.base(this));
        url.setInputType(InputType.TYPE_TEXT_VARIATION_URI);
        layout.addView(url);

        EditText token = new EditText(this);
        token.setHint("Token");
        token.setText(prefs.getString("token", ""));
        token.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        layout.addView(token);

        Button save = new Button(this);
        save.setText("Save");
        save.setOnClickListener(view -> {
            prefs.edit()
                    .putString("url", url.getText().toString().trim())
                    .putString("token", token.getText().toString().trim())
                    .apply();
            Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show();
            retry();
        });
        layout.addView(save);

        Button access = new Button(this);
        access.setText("Notification access");
        access.setOnClickListener(view ->
                startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)));
        layout.addView(access);

        status = new TextView(this);
        layout.addView(status);

        setContentView(layout);
    }

    @Override
    protected void onResume() {
        super.onResume();
        retry();
    }

    private void retry() {
        Context app = getApplicationContext();
        new Thread(() -> {
            RevolutListener.flush(app);
            int left = RevolutListener.pending(app);
            runOnUiThread(() -> status.setText(left + " card payments waiting to send"));
        }).start();
    }
}
