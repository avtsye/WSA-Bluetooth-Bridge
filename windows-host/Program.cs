using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using Windows.Devices.Bluetooth.Advertisement;

const int port = 17890;
var listener = new TcpListener(IPAddress.Loopback, port);
listener.Start();
Console.WriteLine($"WSA Bluetooth Host listening on 127.0.0.1:{port}");

while (true)
{
    using var client = await listener.AcceptTcpClientAsync();
    Console.WriteLine("WSA bridge client connected.");

    try
    {
        await RunSessionAsync(client);
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"Session ended: {ex.Message}");
    }
}

static async Task RunSessionAsync(TcpClient client)
{
    using var stream = client.GetStream();
    using var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);
    using var writer = new StreamWriter(stream, new UTF8Encoding(false), leaveOpen: true)
    {
        AutoFlush = true,
        NewLine = "\n"
    };

    var writeGate = new SemaphoreSlim(1, 1);
    BluetoothLEAdvertisementWatcher? watcher = null;

    async Task SendAsync(object payload)
    {
        var json = JsonSerializer.Serialize(payload);
        await writeGate.WaitAsync();
        try
        {
            await writer.WriteLineAsync(json);
        }
        finally
        {
            writeGate.Release();
        }
    }

    await SendAsync(new
    {
        type = "hello",
        protocol = 1,
        capabilities = new[] { "ble.scan" }
    });

    while (client.Connected)
    {
        var line = await reader.ReadLineAsync();
        if (line is null)
            break;

        JsonDocument request;
        try
        {
            request = JsonDocument.Parse(line);
        }
        catch (JsonException)
        {
            await SendAsync(new { type = "error", code = "invalid_json" });
            continue;
        }

        using (request)
        {
            if (!request.RootElement.TryGetProperty("type", out var typeElement))
            {
                await SendAsync(new { type = "error", code = "missing_type" });
                continue;
            }

            switch (typeElement.GetString())
            {
                case "ping":
                    await SendAsync(new { type = "pong" });
                    break;

                case "scan.start":
                    if (watcher is not null)
                    {
                        await SendAsync(new { type = "scan.state", state = "already_running" });
                        break;
                    }

                    watcher = new BluetoothLEAdvertisementWatcher
                    {
                        ScanningMode = BluetoothLEScanningMode.Active
                    };

                    watcher.Received += async (_, args) =>
                    {
                        var localName = args.Advertisement.LocalName;
                        var serviceUuids = args.Advertisement.ServiceUuids
                            .Select(x => x.ToString())
                            .ToArray();

                        await SendAsync(new
                        {
                            type = "scan.result",
                            address = args.BluetoothAddress.ToString("X12"),
                            rssi = args.RawSignalStrengthInDBm,
                            name = string.IsNullOrWhiteSpace(localName) ? null : localName,
                            serviceUuids,
                            timestamp = args.Timestamp.ToUniversalTime().ToString("O")
                        });
                    };

                    watcher.Stopped += async (_, args) =>
                    {
                        await SendAsync(new
                        {
                            type = "scan.state",
                            state = "stopped",
                            error = args.Error.ToString()
                        });
                    };

                    watcher.Start();
                    await SendAsync(new { type = "scan.state", state = "started" });
                    break;

                case "scan.stop":
                    if (watcher is null)
                    {
                        await SendAsync(new { type = "scan.state", state = "not_running" });
                        break;
                    }

                    watcher.Stop();
                    watcher = null;
                    await SendAsync(new { type = "scan.state", state = "stopped" });
                    break;

                default:
                    await SendAsync(new
                    {
                        type = "error",
                        code = "unsupported_command",
                        command = typeElement.GetString()
                    });
                    break;
            }
        }
    }

    watcher?.Stop();
}
