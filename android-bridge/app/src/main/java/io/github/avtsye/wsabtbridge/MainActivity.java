package io.github.avtsye.wsabtbridge;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.widget.Button;
import android.widget.EditText;
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
    private EditText address;
    private EditText serviceUuid;
    private EditText characteristicUuid;
    private Socket socket;
    private BufferedWriter writer;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 24);

        Button connectHost = new Button(this);
        connectHost.setText("Connect to Windows host");

        Button scan = new Button(this);
        scan.setText("Start BLE scan");

        Button stop = new Button(this);
        stop.setText("Stop BLE scan");

        address = new EditText(this);
        address.setHint("BLE address, e.g. A1B2C3D4E5F6");
        address.setSingleLine(true);
        address.setInputType(InputType.TYPE_CLASS_TEXT);

        Button connectDevice = new Button(this);
        connectDevice.setText("Connect to BLE device");

        Button disconnectDevice = new Button(this);
        disconnectDevice.setText("Disconnect BLE device");

        Button discover = new Button(this);
        discover.setText("Discover GATT services");

        serviceUuid = new EditText(this);
        serviceUuid.setHint("Service UUID");
        serviceUuid.setSingleLine(true);

        characteristicUuid = new EditText(this);
        characteristicUuid.setHint("Characteristic UUID");
        characteristicUuid.setSingleLine(true);

        Button read = new Button(this);
        read.setText("Read GATT characteristic");

        log = new TextView(this);
        log.setTextIsSelectable(true);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(log);

        root.addView(connectHost);
        root.addView(scan);
        root.addView(stop);
        root.addView(address);
        root.addView(connectDevice);
        root.addView(disconnectDevice);
        root.addView(discover);
        root.addView(serviceUuid);
        root.addView(characteristicUuid);
        root.addView(read);
        root.addView(scroll, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1));

        setContentView(root);

        connectHost.setOnClickListener(v -> connect());
        scan.setOnClickListener(v -> send("{\"type\":\"scan.start\"}"));
        stop.setOnClickListener(v -> send("{\"type\":\"scan.stop\"}"));

        connectDevice.setOnClickListener(v -> {
            try {
                JSONObject command = new JSONObject();
                command.put("type", "device.connect");
                command.put("address", address.getText().toString().trim());
                send(command.toString());
            } catch (Exception e) {
                append("Unable to build connect command: " + e);
            }
        });

        disconnectDevice.setOnClickListener(v ->
                send("{\"type\":\"device.disconnect\"}"));

        discover.setOnClickListener(v ->
                send("{\"type\":\"gatt.discover\"}"));

        read.setOnClickListener(v -> {
            try {
                JSONObject command = new JSONObject();
                command.put("type", "gatt.read");
                command.put("service", serviceUuid.getText().toString().trim());
                command.put("characteristic", characteristicUuid.getText().toString().trim());
                send(command.toString());
            } catch (Exception e) {
                append("Unable to build read command: " + e);
            }
        });
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
