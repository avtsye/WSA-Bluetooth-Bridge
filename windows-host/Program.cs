using System.Collections.Concurrent;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Storage.Streams;

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
        Console.Error.WriteLine($"Session ended: {ex}");
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
    BluetoothLEDevice? device = null;
    var resolvingNames = new ConcurrentDictionary<ulong, byte>();

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
        capabilities = new[]
        {
            "ble.scan",
            "ble.connect",
            "gatt.discover",
            "gatt.read"
        }
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

            try
            {
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
                                nameSource = string.IsNullOrWhiteSpace(localName) ? null : "advertisement",
                                serviceUuids,
                                timestamp = args.Timestamp.ToUniversalTime().ToString("O")
                            });

                            // Many BLE peripherals omit Local Name from their advertisements.
                            // Resolve a friendly Windows device name once per address and send an
                            // updated scan result when one is available.
                            if (string.IsNullOrWhiteSpace(localName) &&
                                resolvingNames.TryAdd(args.BluetoothAddress, 0))
                            {
                                try
                                {
                                    using var discoveredDevice =
                                        await BluetoothLEDevice.FromBluetoothAddressAsync(args.BluetoothAddress);

                                    if (discoveredDevice is not null &&
                                        !string.IsNullOrWhiteSpace(discoveredDevice.Name))
                                    {
                                        await SendAsync(new
                                        {
                                            type = "scan.result",
                                            address = args.BluetoothAddress.ToString("X12"),
                                            rssi = args.RawSignalStrengthInDBm,
                                            name = discoveredDevice.Name,
                                            nameSource = "windows-device",
                                            serviceUuids,
                                            timestamp = args.Timestamp.ToUniversalTime().ToString("O")
                                        });
                                    }
                                }
                                catch
                                {
                                    // Name resolution is best-effort; scanning must continue.
                                }
                            }
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

                    case "device.connect":
                    {
                        if (!request.RootElement.TryGetProperty("address", out var addressElement) ||
                            !TryParseAddress(addressElement.GetString(), out var address))
                        {
                            await SendAsync(new { type = "error", code = "invalid_address" });
                            break;
                        }

                        device?.Dispose();
                        device = await BluetoothLEDevice.FromBluetoothAddressAsync(address);
                        if (device is null)
                        {
                            await SendAsync(new
                            {
                                type = "device.connection",
                                state = "failed",
                                address = address.ToString("X12"),
                                error = "device_not_available"
                            });
                            break;
                        }

                        // Requesting uncached services forces real GATT traffic and is a much
                        // stronger end-to-end test than merely creating BluetoothLEDevice.
                        var probe = await device.GetGattServicesAsync(BluetoothCacheMode.Uncached);

                        await SendAsync(new
                        {
                            type = "device.connection",
                            state = probe.Status == GattCommunicationStatus.Success ? "connected" : "failed",
                            address = address.ToString("X12"),
                            name = device.Name,
                            windowsStatus = device.ConnectionStatus.ToString(),
                            gattStatus = probe.Status.ToString(),
                            serviceCount = probe.Services.Count
                        });
                        break;
                    }

                    case "device.disconnect":
                        if (device is not null)
                        {
                            var address = device.BluetoothAddress.ToString("X12");
                            device.Dispose();
                            device = null;
                            await SendAsync(new
                            {
                                type = "device.connection",
                                state = "disconnected",
                                address
                            });
                        }
                        else
                        {
                            await SendAsync(new { type = "device.connection", state = "not_connected" });
                        }
                        break;

                    case "gatt.discover":
                    {
                        if (device is null)
                        {
                            await SendAsync(new { type = "error", code = "not_connected" });
                            break;
                        }

                        var servicesResult =
                            await device.GetGattServicesAsync(BluetoothCacheMode.Uncached);

                        if (servicesResult.Status != GattCommunicationStatus.Success)
                        {
                            await SendAsync(new
                            {
                                type = "gatt.services",
                                status = servicesResult.Status.ToString(),
                                services = Array.Empty<object>()
                            });
                            break;
                        }

                        var services = new List<object>();
                        foreach (var service in servicesResult.Services)
                        {
                            var charsResult =
                                await service.GetCharacteristicsAsync(BluetoothCacheMode.Uncached);

                            var characteristics = charsResult.Status == GattCommunicationStatus.Success
                                ? charsResult.Characteristics.Select(c => new
                                {
                                    uuid = c.Uuid.ToString(),
                                    properties = c.CharacteristicProperties.ToString()
                                }).Cast<object>().ToArray()
                                : Array.Empty<object>();

                            services.Add(new
                            {
                                uuid = service.Uuid.ToString(),
                                characteristicsStatus = charsResult.Status.ToString(),
                                characteristics
                            });
                        }

                        await SendAsync(new
                        {
                            type = "gatt.services",
                            status = servicesResult.Status.ToString(),
                            services
                        });
                        break;
                    }

                    case "gatt.read":
                    {
                        if (device is null)
                        {
                            await SendAsync(new { type = "error", code = "not_connected" });
                            break;
                        }

                        if (!TryGetUuid(request.RootElement, "service", out var serviceUuid) ||
                            !TryGetUuid(request.RootElement, "characteristic", out var characteristicUuid))
                        {
                            await SendAsync(new { type = "error", code = "invalid_uuid" });
                            break;
                        }

                        var servicesResult =
                            await device.GetGattServicesForUuidAsync(serviceUuid, BluetoothCacheMode.Uncached);

                        if (servicesResult.Status != GattCommunicationStatus.Success ||
                            servicesResult.Services.Count == 0)
                        {
                            await SendAsync(new
                            {
                                type = "gatt.read.result",
                                status = servicesResult.Status.ToString(),
                                error = "service_not_found"
                            });
                            break;
                        }

                        var charsResult = await servicesResult.Services[0]
                            .GetCharacteristicsForUuidAsync(characteristicUuid, BluetoothCacheMode.Uncached);

                        if (charsResult.Status != GattCommunicationStatus.Success ||
                            charsResult.Characteristics.Count == 0)
                        {
                            await SendAsync(new
                            {
                                type = "gatt.read.result",
                                status = charsResult.Status.ToString(),
                                error = "characteristic_not_found"
                            });
                            break;
                        }

                        var readResult =
                            await charsResult.Characteristics[0].ReadValueAsync(BluetoothCacheMode.Uncached);

                        await SendAsync(new
                        {
                            type = "gatt.read.result",
                            status = readResult.Status.ToString(),
                            service = serviceUuid.ToString(),
                            characteristic = characteristicUuid.ToString(),
                            valueHex = readResult.Status == GattCommunicationStatus.Success
                                ? BufferToHex(readResult.Value)
                                : null
                        });
                        break;
                    }

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
            catch (Exception ex)
            {
                await SendAsync(new
                {
                    type = "error",
                    code = "host_exception",
                    message = ex.Message
                });
            }
        }
    }

    watcher?.Stop();
    device?.Dispose();
}

static bool TryParseAddress(string? value, out ulong address)
{
    address = 0;
    if (string.IsNullOrWhiteSpace(value))
        return false;

    var normalized = value.Replace(":", "").Replace("-", "").Trim();
    return ulong.TryParse(normalized, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out address);
}

static bool TryGetUuid(JsonElement root, string propertyName, out Guid value)
{
    value = Guid.Empty;
    return root.TryGetProperty(propertyName, out var element) &&
           Guid.TryParse(element.GetString(), out value);
}

static string BufferToHex(IBuffer buffer)
{
    if (buffer.Length == 0)
        return string.Empty;

    using var reader = DataReader.FromBuffer(buffer);
    var bytes = new byte[buffer.Length];
    reader.ReadBytes(bytes);
    return Convert.ToHexString(bytes);
}
