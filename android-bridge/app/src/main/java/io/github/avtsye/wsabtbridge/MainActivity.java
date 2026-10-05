package io.github.avtsye.wsabtbridge;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

public final class MainActivity extends Activity {
    private final Handler main = new Handler(Looper.getMainLooper());
    private TextView log;
    private Socket socket;
    private BufferedWriter writer;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        Button connect = new Button(this);
        connect.setText("Connect to Windows host");
        Button scan = new Button(this);
        scan.setText("Start BLE scan");
        Button stop = new Button(this);
        stop.setText("Stop BLE scan");

        log = new TextView(this);
        log.setTextIsSelectable(true);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(log);

        root.addView(connect);
        root.addView(scan);
        root.addView(stop);
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));

        setContentView(root);

        connect.setOnClickListener(v -> connect());
        scan.setOnClickListener(v -> send("{\"type\":\"scan.start\"}"));
        stop.setOnClickListener(v -> send("{\"type\":\"scan.stop\"}"));
    }

    private void connect() {
        append("Connecting to 127.0.0.1:17890 ...");
        new Thread(() -> {
            try {
                Socket s = new Socket();
                s.connect(new InetSocketAddress("127.0.0.1", 17890), 5000);
                BufferedReader reader = new BufferedReader(new InputStreamReader(
                        s.getInputStream(), StandardCharsets.UTF_8));
                BufferedWriter w = new BufferedWriter(new OutputStreamWriter(
                        s.getOutputStream(), StandardCharsets.UTF_8));

                socket = s;
                writer = w;
                append("Connected.");

                String line;
                while ((line = reader.readLine()) != null) {
                    try {
                        JSONObject object = new JSONObject(line);
                        append(object.toString(2));
                    } catch (Exception ignored) {
                        append(line);
                    }
                }

                append("Host disconnected.");
            } catch (Exception e) {
                append("Connection failed: " + e);
            }
        }, "wsa-bt-reader").start();
    }

    private void send(String json) {
        new Thread(() -> {
            try {
                BufferedWriter w = writer;
                if (w == null) {
                    append("Not connected.");
                    return;
                }
                synchronized (this) {
                    w.write(json);
                    w.write("\n");
                    w.flush();
                }
            } catch (Exception e) {
                append("Send failed: " + e);
            }
        }, "wsa-bt-writer").start();
    }

    private void append(String text) {
        main.post(() -> log.append(text + "\n\n"));
    }

    @Override
    protected void onDestroy() {
        try {
            if (socket != null) socket.close();
        } catch (Exception ignored) {
        }
        super.onDestroy();
    }
}
