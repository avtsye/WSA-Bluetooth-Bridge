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
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
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
    private Spinner audioInputsSpinner;
    private final ArrayList<String> audioInputIds = new ArrayList<>();
    private final ArrayList<String> audioInputNames = new ArrayList<>();
    private ArrayAdapter<String> audioInputAdapter;
    private TextView audioStatus;
    private EditText serviceUuid;
    private EditText characteristicUuid;
    private Socket socket;
    private BufferedWriter writer;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        ScrollView screenScroll = new ScrollView(this);
        screenScroll.setFillViewport(true);
        screenScroll.setVerticalScrollBarEnabled(true);
        screenScroll.setScrollbarFadingEnabled(false);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 24, 24, 48);
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        root.setTextDirection(View.TEXT_DIRECTION_RTL);

        screenScroll.addView(root, new ScrollView.LayoutParams(
                ScrollView.LayoutParams.MATCH_PARENT,
                ScrollView.LayoutParams.WRAP_CONTENT));

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
        loadAudioOutputs.setText("טען יציאות שמע ומיקרופונים של Windows");

        audioOutputsSpinner = new Spinner(this);
        audioAdapter = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item, audioEndpointNames);
        audioOutputsSpinner.setAdapter(audioAdapter);

        audioInputsSpinner = new Spinner(this);
        audioInputAdapter = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item, audioInputNames);
        audioInputsSpinner.setAdapter(audioInputAdapter);

        Button playTestTone = new Button(this);
        playTestTone.setText("השמע צליל בדיקה באוזניה שנבחרה");

        Button duplexTest = new Button(this);
        duplexTest.setText("בדיקת Duplex: שמע יוצא + מיקרופון חוזר");

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

        log.setPadding(0, 16, 0, 24);
        log.setMinLines(6);

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
        root.addView(audioInputsSpinner);
        root.addView(playTestTone);
        root.addView(duplexTest);
        root.addView(audioStatus);
        root.addView(discover);
        root.addView(serviceUuid);
        root.addView(characteristicUuid);
        root.addView(read);
        root.addView(log, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT));

        setContentView(screenScroll);

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
                send("{\"type\":\"audio.routes\"}"));

        duplexTest.setOnClickListener(v -> runDuplexAudioTest());

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
                        } else if ("audio.routes.result".equals(type)) {
                            updateAudioRoutes(object);
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

    private void updateAudioRoutes(JSONObject object) {
        JSONArray render = object.optJSONArray("render");
        JSONArray capture = object.optJSONArray("capture");

        main.post(() -> {
            audioEndpointIds.clear();
            audioEndpointNames.clear();
            audioInputIds.clear();
            audioInputNames.clear();

            if (render != null) {
                for (int i = 0; i < render.length(); i++) {
                    JSONObject item = render.optJSONObject(i);
                    if (item == null) continue;
                    String id = item.optString("id", "");
                    if (id.isEmpty()) continue;
                    audioEndpointIds.add(id);
                    audioEndpointNames.add(item.optString("name", "יציאת שמע ללא שם"));
                }
            }

            if (capture != null) {
                for (int i = 0; i < capture.length(); i++) {
                    JSONObject item = capture.optJSONObject(i);
                    if (item == null) continue;
                    String id = item.optString("id", "");
                    if (id.isEmpty()) continue;
                    audioInputIds.add(id);
                    audioInputNames.add(item.optString("name", "מיקרופון ללא שם"));
                }
            }

            audioAdapter.notifyDataSetChanged();
            audioInputAdapter.notifyDataSetChanged();

            audioStatus.setText(
                    "נמצאו " + audioEndpointIds.size() + " יציאות שמע ו־" +
                    audioInputIds.size() + " כניסות מיקרופון."
            );
        });
    }

    private void runDuplexAudioTest() {
        int renderPosition = audioOutputsSpinner.getSelectedItemPosition();
        int capturePosition = audioInputsSpinner.getSelectedItemPosition();

        if (renderPosition < 0 || renderPosition >= audioEndpointIds.size()) {
            audioStatus.setText("❌ בחר יציאת שמע לאוזניה");
            return;
        }
        if (capturePosition < 0 || capturePosition >= audioInputIds.size()) {
            audioStatus.setText("❌ בחר את מיקרופון האוזניה");
            return;
        }

        final String renderId = audioEndpointIds.get(renderPosition);
        final String captureId = audioInputIds.get(capturePosition);

        audioStatus.setText("בדיקת Duplex: מכין שמע ומיקרופון...");

        new Thread(() -> {
            Socket audioSocket = null;
            try {
                JSONObject route = new JSONObject();
                route.put("type", "audio.route.select");
                route.put("renderEndpointId", renderId);
                route.put("captureEndpointId", captureId);
                send(route.toString());

                JSONObject playback = new JSONObject();
                playback.put("type", "audio.playback.start");
                playback.put("sampleRate", 48000);
                playback.put("channels", 2);
                playback.put("sampleFormat", "s16le");
                send(playback.toString());

                send("{\"type\":\"audio.capture.start\"}");
                Thread.sleep(500);

                audioSocket = new Socket();
                audioSocket.connect(new InetSocketAddress("127.0.0.1", 17891), 5000);
                audioSocket.setSoTimeout(4000);

                DataOutputStream output = new DataOutputStream(audioSocket.getOutputStream());
                DataInputStream input = new DataInputStream(audioSocket.getInputStream());

                byte[] pcm = createTestTonePcm(48000, 2, 880.0, 1000);
                int offset = 0;
                int sequence = 0;
                final int frameBytes = 3840;

                while (offset < pcm.length) {
                    int size = Math.min(frameBytes, pcm.length - offset);
                    writeAudioFrame(output, 1, sequence++, pcm, offset, size);
                    offset += size;
                    Thread.sleep(18);
                }
                output.flush();

                long deadline = System.currentTimeMillis() + 3000;
                long capturedBytes = 0;
                int captureFrames = 0;
                byte[] header = new byte[16];

                while (System.currentTimeMillis() < deadline) {
                    try {
                        input.readFully(header);
                    } catch (java.net.SocketTimeoutException timeout) {
                        break;
                    }

                    if (header[0] != 'W' || header[1] != 'S' ||
                            header[2] != 'A' || header[3] != 'B') {
                        throw new IllegalStateException("כותרת WSAB לא תקינה");
                    }

                    ByteBuffer hb = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);
                    int streamId = header[5] & 0xFF;
                    int length = hb.getInt(8);
                    if (length < 0 || length > 1024 * 1024) {
                        throw new IllegalStateException("מסגרת אודיו גדולה מדי");
                    }

                    byte[] payload = new byte[length];
                    input.readFully(payload);

                    if (streamId == 2) {
                        capturedBytes += length;
                        captureFrames++;
                        if (capturedBytes >= 4096) break;
                    }
                }

                final long finalCapturedBytes = capturedBytes;
                final int finalCaptureFrames = captureFrames;
                main.post(() -> {
                    if (finalCapturedBytes > 0) {
                        audioStatus.setText(
                                "✅ Duplex עובד בשני הכיוונים\n" +
                                "נשלח PCM לאוזניה ונקלטו " + finalCapturedBytes +
                                " בתים מהמיקרופון (" + finalCaptureFrames + " מסגרות)."
                        );
                    } else {
                        audioStatus.setText(
                                "⚠️ האודיו היוצא נשלח, אבל לא התקבל PCM מהמיקרופון.\n" +
                                "בדוק שנבחר מיקרופון של אותה אוזניה."
                        );
                    }
                });
            } catch (Exception e) {
                final String message = e.toString();
                main.post(() -> audioStatus.setText("❌ בדיקת Duplex נכשלה\n" + message));
            } finally {
                send("{\"type\":\"audio.capture.stop\"}");
                send("{\"type\":\"audio.playback.stop\"}");
                try {
                    if (audioSocket != null) audioSocket.close();
                } catch (Exception ignored) {
                }
            }
        }, "wsa-audio-duplex-test").start();
    }

    private static byte[] createTestTonePcm(int sampleRate, int channels,
                                             double frequency, int durationMs) {
        int frames = sampleRate * durationMs / 1000;
        ByteBuffer buffer = ByteBuffer.allocate(frames * channels * 2)
                .order(ByteOrder.LITTLE_ENDIAN);

        for (int i = 0; i < frames; i++) {
            double phase = 2.0 * Math.PI * frequency * i / sampleRate;
            short sample = (short) (Math.sin(phase) * 0.12 * Short.MAX_VALUE);
            for (int channel = 0; channel < channels; channel++) {
                buffer.putShort(sample);
            }
        }
        return buffer.array();
    }

    private static void writeAudioFrame(DataOutputStream output, int streamId,
                                        int sequence, byte[] data, int offset, int length)
            throws Exception {
        ByteBuffer header = ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN);
        header.put((byte) 'W');
        header.put((byte) 'S');
        header.put((byte) 'A');
        header.put((byte) 'B');
        header.put((byte) 1);
        header.put((byte) streamId);
        header.putShort((short) 0);
        header.putInt(length);
        header.putInt(sequence);

        output.write(header.array());
        output.write(data, offset, length);
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
