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

import org.json.JSONArray;
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
    private TextView connectionStatus;
    private EditText address;
    private Spinner devicesSpinner;
    private final Map<String, String> deviceLabels = new LinkedHashMap<>();
    private final Map<String, String> deviceNames = new LinkedHashMap<>();
    private final ArrayList<String> deviceAddresses = new ArrayList<>();
    private final ArrayList<String> deviceDisplay = new ArrayList<>();
    private ArrayAdapter<String> deviceAdapter;
    private Spinner audioOutputsSpinner;
    private final ArrayList<String> audioEndpointIds = new ArrayList<>();
    private final ArrayList<String> audioEndpointNames = new ArrayList<>();
    private ArrayAdapter<String> audioAdapter;
    private TextView audioStatus;
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

        connectionStatus = new TextView(this);
        connectionStatus.setText("סטטוס התקן: לא נבדק");
        connectionStatus.setTextSize(18);
        connectionStatus.setGravity(Gravity.CENTER);
        connectionStatus.setPadding(12, 18, 12, 18);

        Button connectDevice = new Button(this);
        connectDevice.setText("התחבר ובדוק חיבור אמיתי");

        Button disconnectDevice = new Button(this);
        disconnectDevice.setText("נתק את ההתקן");

        TextView audioTitle = new TextView(this);
        audioTitle.setText("בדיקת שמע דו־כיוונית");
        audioTitle.setTextSize(18);
        audioTitle.setGravity(Gravity.CENTER);
        audioTitle.setPadding(0, 18, 0, 8);

        Button loadAudioOutputs = new Button(this);
        loadAudioOutputs.setText("טען יציאות שמע של Windows");

        audioOutputsSpinner = new Spinner(this);
        audioAdapter = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item, audioEndpointNames);
        audioOutputsSpinner.setAdapter(audioAdapter);

        Button playTestTone = new Button(this);
        playTestTone.setText("השמע צליל בדיקה באוזניה שנבחרה");

        audioStatus = new TextView(this);
        audioStatus.setText("בדיקת שמע: טרם בוצעה");
        audioStatus.setTextSize(17);
        audioStatus.setGravity(Gravity.CENTER);
        audioStatus.setPadding(12, 12, 12, 18);

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
        root.addView(connectionStatus);
        root.addView(connectDevice);
        root.addView(disconnectDevice);
        root.addView(audioTitle);
        root.addView(loadAudioOutputs);
        root.addView(audioOutputsSpinner);
        root.addView(playTestTone);
        root.addView(audioStatus);
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
            connectionStatus.setText("סטטוס התקן: בודק חיבור ו־GATT...");
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

        loadAudioOutputs.setOnClickListener(v ->
                send("{\"type\":\"audio.outputs\"}"));

        playTestTone.setOnClickListener(v -> {
            int position = audioOutputsSpinner.getSelectedItemPosition();
            if (position < 0 || position >= audioEndpointIds.size()) {
                audioStatus.setText("❌ לא נבחרה יציאת שמע");
                return;
            }
            audioStatus.setText("בדיקת שמע: משמיע צליל...");
            try {
                JSONObject command = new JSONObject();
                command.put("type", "audio.test");
                command.put("endpointId", audioEndpointIds.get(position));
                send(command.toString());
            } catch (Exception e) {
                audioStatus.setText("❌ לא ניתן לשלוח את בדיקת השמע: " + e.getMessage());
            }
        });

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
                        } else if ("device.connection".equals(type)) {
                            updateConnectionStatus(object);
                        } else if ("audio.outputs.result".equals(type)) {
                            updateAudioOutputs(object);
                        } else if ("audio.test.result".equals(type)) {
                            updateAudioTestStatus(object);
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

    private void updateAudioOutputs(JSONObject object) {
        JSONArray outputs = object.optJSONArray("outputs");
        if (outputs == null) return;

        main.post(() -> {
            audioEndpointIds.clear();
            audioEndpointNames.clear();

            for (int i = 0; i < outputs.length(); i++) {
                JSONObject item = outputs.optJSONObject(i);
                if (item == null) continue;

                String id = item.optString("id", "");
                String name = item.optString("name", "יציאת שמע ללא שם");
                if (id.isEmpty()) continue;

                audioEndpointIds.add(id);
                audioEndpointNames.add(name);
            }

            audioAdapter.notifyDataSetChanged();

            if (audioEndpointIds.isEmpty()) {
                audioStatus.setText("❌ Windows לא החזיר יציאות שמע פעילות");
            } else {
                audioStatus.setText("נמצאו " + audioEndpointIds.size() + " יציאות שמע. בחר אוזניה ובדוק.");
            }
        });
    }

    private void updateAudioTestStatus(JSONObject object) {
        final boolean success = object.optBoolean("success", false);
        final String endpointName = object.optString("endpointName", "");
        final String error = object.optString("error", "");

        main.post(() -> {
            if (success) {
                audioStatus.setText(
                        "🔊 צליל הבדיקה נשלח אל:\n" +
                        (endpointName.isEmpty() ? "יציאת השמע שנבחרה" : endpointName) +
                        "\nאם שמעת את הצליל באוזניה — הכיוון WSA → Windows → אוזניה עובד."
                );
            } else {
                audioStatus.setText(
                        "❌ שליחת צליל הבדיקה נכשלה" +
                        (error.isEmpty() ? "" : "\n" + error)
                );
            }
        });
    }

    private void updateConnectionStatus(JSONObject object) {
        final String state = object.optString("state", "");
        final boolean verified = object.optBoolean("verified", false);
        final String name = object.optString("name", "").trim();
        final String addressValue = object.optString("address", "").trim();
        final String gattStatus = object.optString("gattStatus", "");
        final int serviceCount = object.optInt("serviceCount", 0);

        main.post(() -> {
            if ("connected".equals(state) && verified) {
                String deviceText = name.isEmpty() ? addressValue : name;
                connectionStatus.setText(
                        "✅ חיבור BLE אמיתי אושר\n" +
                        deviceText +
                        "\nGATT: " + gattStatus +
                        " • שירותים: " + serviceCount
                );
            } else if ("disconnected".equals(state)) {
                connectionStatus.setText("סטטוס התקן: מנותק");
            } else if ("not_connected".equals(state)) {
                connectionStatus.setText("סטטוס התקן: אין התקן מחובר");
            } else {
                String reason = gattStatus.isEmpty() ? object.optString("error", "לא ידוע") : gattStatus;
                connectionStatus.setText("❌ החיבור לא אומת\nסיבה: " + reason);
            }
        });
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
