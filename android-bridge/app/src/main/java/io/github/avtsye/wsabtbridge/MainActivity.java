package io.github.avtsye.wsabtbridge;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ArrayAdapter;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;

public final class MainActivity extends Activity {
    private final Handler main = new Handler(Looper.getMainLooper());
    private TextView log;
    private EditText address;
    private Spinner devicesSpinner;
    private final Map<String, String> deviceLabels = new LinkedHashMap<>();
    private final Map<String, String> deviceNames = new LinkedHashMap<>();
    private final ArrayList<String> deviceAddresses = new ArrayList<>();
    private final ArrayList<String> deviceDisplay = new ArrayList<>();
    private ArrayAdapter<String> deviceAdapter;
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
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        root.setTextDirection(View.TEXT_DIRECTION_RTL);

        TextView title = new TextView(this);
        title.setText("גשר Bluetooth ל־WSA");
        title.setTextSize(22);
        title.setGravity(Gravity.CENTER_HORIZONTAL);
        title.setPadding(0, 0, 0, 16);

        Button connectHost = new Button(this);
        connectHost.setText("התחבר לשירות Bluetooth של Windows");

        Button scan = new Button(this);
        scan.setText("התחל סריקת BLE");

        Button stop = new Button(this);
        stop.setText("עצור סריקה");

        Button deepScan = new Button(this);
        deepScan.setText("סריקה עמוקה: BLE + Bluetooth Classic + התקנים מוכרים");

        devicesSpinner = new Spinner(this);
        deviceAdapter = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item, deviceDisplay);
        devicesSpinner.setAdapter(deviceAdapter);

        address = new EditText(this);
        address.setHint("כתובת BLE, לדוגמה A1B2C3D4E5F6");
        address.setSingleLine(true);
        address.setInputType(InputType.TYPE_CLASS_TEXT);

        Button connectDevice = new Button(this);
        connectDevice.setText("התחבר להתקן שנבחר");

        Button disconnectDevice = new Button(this);
        disconnectDevice.setText("נתק את ההתקן");

        Button discover = new Button(this);
        discover.setText("טען שירותי GATT");

        serviceUuid = new EditText(this);
        serviceUuid.setHint("UUID של השירות");
        serviceUuid.setSingleLine(true);

        characteristicUuid = new EditText(this);
        characteristicUuid.setHint("UUID של המאפיין");
        characteristicUuid.setSingleLine(true);

        Button read = new Button(this);
        read.setText("קרא ערך GATT");

        log = new TextView(this);
        log.setTextIsSelectable(true);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(log);

        root.addView(title);
        root.addView(connectHost);
        root.addView(scan);
        root.addView(stop);
        root.addView(deepScan);
        root.addView(devicesSpinner);
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
        deepScan.setOnClickListener(v -> send("{\"type\":\"scan.deep\"}"));

        devicesSpinner.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(android.widget.AdapterView<?> parent, android.view.View view,
                                       int position, long id) {
                if (position >= 0 && position < deviceAddresses.size()) {
                    address.setText(deviceAddresses.get(position));
                }
            }

            @Override
            public void onNothingSelected(android.widget.AdapterView<?> parent) {
            }
        });

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
        append("מתחבר לשירות Windows ב־127.0.0.1:17890...");
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
                append("מחובר לשירות Windows.");

                String line;
                while ((line = reader.readLine()) != null) {
                    try {
                        JSONObject object = new JSONObject(line);
                        String type = object.optString("type");
                        if ("scan.result".equals(type) || "device.catalog.result".equals(type)) {
                            updateDeviceList(object);
                        }
                        append(object.toString(2));
                    } catch (Exception ignored) {
                        append(line);
                    }
                }

                append("החיבור לשירות Windows נותק.");
            } catch (Exception e) {
                append("החיבור נכשל: " + e);
            }
        }, "wsa-bt-reader").start();
    }

    private void updateDeviceList(JSONObject object) {
        final String foundAddress = object.optString("address", "").trim();
        if (foundAddress.isEmpty()) return;

        final String incomingName = object.optString("name", "").trim();
        final int rssi = object.optInt("rssi", Integer.MIN_VALUE);
        final String transport = object.optString("transport", "BLE").trim();
        final boolean paired = object.optBoolean("paired", false);
        final boolean connected = object.optBoolean("connected", false);

        main.post(() -> {
            String currentName = deviceNames.get(foundAddress);

            // Never replace a real resolved name with an empty advertisement name.
            // Prefer the longer non-empty name because advertising names are commonly shortened.
            if (!incomingName.isEmpty() &&
                    (currentName == null || currentName.isEmpty() ||
                     incomingName.length() > currentName.length())) {
                deviceNames.put(foundAddress, incomingName);
                currentName = incomingName;
            }

            if (currentName == null || currentName.isEmpty()) {
                currentName = "התקן ללא שם";
            }

            StringBuilder label = new StringBuilder();
            label.append(currentName).append("\n")
                    .append(foundAddress)
                    .append("   •   ")
                    .append(transport);

            if (rssi != Integer.MIN_VALUE) {
                label.append("   •   RSSI ").append(rssi);
            }
            if (paired) {
                label.append("   •   מזווג");
            }
            if (connected) {
                label.append("   •   מחובר");
            }

            deviceLabels.put(foundAddress, label.toString());
            deviceAddresses.clear();
            deviceDisplay.clear();

            for (Map.Entry<String, String> entry : deviceLabels.entrySet()) {
                deviceAddresses.add(entry.getKey());
                deviceDisplay.add(entry.getValue());
            }

            deviceAdapter.notifyDataSetChanged();
        });
    }

    private void send(String json) {
        new Thread(() -> {
            try {
                BufferedWriter w = writer;
                if (w == null) {
                    append("אין חיבור לשירות Windows.");
                    return;
                }
                synchronized (this) {
                    w.write(json);
                    w.write("\n");
                    w.flush();
                }
            } catch (Exception e) {
                append("שליחת הפקודה נכשלה: " + e);
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
