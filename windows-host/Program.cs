using System.Collections.Concurrent;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
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
            "bluetooth.deep-scan",
            "ble.connect",
            "gatt.discover",
            "gatt.read",
            "audio.outputs",
            "audio.test"
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

                        watcher.Received += async (sender, args) =>
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
                                manufacturerData = args.Advertisement.ManufacturerData.Select(m => new
                                {
                                    companyId = m.CompanyId,
                                    dataHex = BufferToHex(m.Data)
                                }).ToArray(),
                                transport = "BLE-advertisement",
                                timestamp = args.Timestamp.ToUniversalTime().ToString("O")
                            });

                            // Advertisement names are often absent or shortened. Resolve the
                            // Windows DeviceInformation name once for every address and send an
                            // updated result even when the advertisement already had a short name.
                            if (resolvingNames.TryAdd(args.BluetoothAddress, 0))
                            {
                                Task.Run(async () =>
                                {
                                    try
                                    {
                                        var resolvedName =
                                            await ResolveFriendlyNameAsync(args.BluetoothAddress);

                                        if (!string.IsNullOrWhiteSpace(resolvedName) &&
                                            !string.Equals(resolvedName, localName,
                                                StringComparison.Ordinal))
                                        {
                                            await SendAsync(new
                                            {
                                                type = "scan.result",
                                                address = args.BluetoothAddress.ToString("X12"),
                                                rssi = args.RawSignalStrengthInDBm,
                                                name = resolvedName,
                                                nameSource = "windows-device-information",
                                                serviceUuids,
                                                transport = "BLE-advertisement",
                                                timestamp = DateTimeOffset.UtcNow.ToString("O")
                                            });
                                        }
                                    }
                                    catch
                                    {
                                        // Friendly-name resolution is best-effort only.
                                    }
                                });
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

                    case "scan.deep":
                    {
                        await SendAsync(new { type = "deep.scan.state", state = "started" });

                        var seenIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        var properties = new[]
                        {
                            "System.ItemNameDisplay",
                            "System.Devices.FriendlyName",
                            "System.Devices.Aep.IsPaired",
                            "System.Devices.Aep.IsConnected"
                        };

                        async Task EmitBleCatalogAsync(string selector, string source)
                        {
                            var infos = await DeviceInformation.FindAllAsync(selector, properties);
                            foreach (var info in infos)
                            {
                                if (!seenIds.Add("ble:" + info.Id))
                                    continue;

                                try
                                {
                                    using var bleDevice = await BluetoothLEDevice.FromIdAsync(info.Id);
                                    if (bleDevice is null)
                                        continue;

                                    var friendlyName = BestDeviceInformationName(info);
                                    if (string.IsNullOrWhiteSpace(friendlyName))
                                        friendlyName = bleDevice.Name;

                                    await SendAsync(new
                                    {
                                        type = "device.catalog.result",
                                        transport = "BLE",
                                        source,
                                        address = bleDevice.BluetoothAddress.ToString("X12"),
                                        name = string.IsNullOrWhiteSpace(friendlyName) ? null : friendlyName,
                                        paired = info.Pairing.IsPaired,
                                        connected = bleDevice.ConnectionStatus == BluetoothConnectionStatus.Connected,
                                        deviceId = info.Id
                                    });
                                }
                                catch
                                {
                                    // Enumeration is diagnostic: one inaccessible device must not stop it.
                                }
                            }
                        }

                        async Task EmitClassicCatalogAsync(string selector, string source)
                        {
                            var infos = await DeviceInformation.FindAllAsync(selector, properties);
                            foreach (var info in infos)
                            {
                                if (!seenIds.Add("classic:" + info.Id))
                                    continue;

                                try
                                {
                                    using var classicDevice = await BluetoothDevice.FromIdAsync(info.Id);
                                    if (classicDevice is null)
                                        continue;

                                    var friendlyName = BestDeviceInformationName(info);
                                    if (string.IsNullOrWhiteSpace(friendlyName))
                                        friendlyName = classicDevice.Name;

                                    await SendAsync(new
                                    {
                                        type = "device.catalog.result",
                                        transport = "Classic",
                                        source,
                                        address = classicDevice.BluetoothAddress.ToString("X12"),
                                        name = string.IsNullOrWhiteSpace(friendlyName) ? null : friendlyName,
                                        paired = info.Pairing.IsPaired,
                                        connected = classicDevice.ConnectionStatus == BluetoothConnectionStatus.Connected,
                                        deviceId = info.Id
                                    });
                                }
                                catch
                                {
                                }
                            }
                        }

                        try
                        {
                            await EmitBleCatalogAsync(BluetoothLEDevice.GetDeviceSelector(), "windows-ble-catalog");
                        }
                        catch (Exception ex)
                        {
                            await SendAsync(new
                            {
                                type = "deep.scan.warning",
                                source = "windows-ble-catalog",
                                message = ex.Message
                            });
                        }

                        try
                        {
                            await EmitClassicCatalogAsync(BluetoothDevice.GetDeviceSelector(), "windows-classic-catalog");
                        }
                        catch (Exception ex)
                        {
                            await SendAsync(new
                            {
                                type = "deep.scan.warning",
                                source = "windows-classic-catalog",
                                message = ex.Message
                            });
                        }

                        await SendAsync(new
                        {
                            type = "deep.scan.state",
                            state = "finished",
                            catalogEntries = seenIds.Count
                        });
                        break;
                    }

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

                    case "audio.outputs":
                    {
                        using var enumerator = new MMDeviceEnumerator();
                        var outputs = enumerator
                            .EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active)
                            .Select(endpoint => new
                            {
                                id = endpoint.ID,
                                name = endpoint.FriendlyName,
                                state = endpoint.State.ToString()
                            })
                            .ToArray();

                        await SendAsync(new
                        {
                            type = "audio.outputs.result",
                            outputs
                        });
                        break;
                    }

                    case "audio.test":
                    {
                        if (!request.RootElement.TryGetProperty("endpointId", out var endpointElement) ||
                            string.IsNullOrWhiteSpace(endpointElement.GetString()))
                        {
                            await SendAsync(new
                            {
                                type = "audio.test.result",
                                success = false,
                                error = "missing_endpoint"
                            });
                            break;
                        }

                        var endpointId = endpointElement.GetString()!;
                        using var enumerator = new MMDeviceEnumerator();
                        MMDevice? endpoint = null;

                        try
                        {
                            endpoint = enumerator.GetDevice(endpointId);
                        }
                        catch
                        {
                        }

                        if (endpoint is null)
                        {
                            await SendAsync(new
                            {
                                type = "audio.test.result",
                                success = false,
                                endpointId,
                                error = "endpoint_not_found"
                            });
                            break;
                        }

                        try
                        {
                            var signal = new SignalGenerator(44100, 1)
                            {
                                Gain = 0.12,
                                Frequency = 880,
                                Type = SignalGeneratorType.Sin
                            };

                            using var output = new WasapiOut(
                                endpoint,
                                AudioClientShareMode.Shared,
                                true,
                                100);

                            output.Init(signal.ToWaveProvider16());
                            output.Play();
                            await Task.Delay(900);
                            output.Stop();

                            await SendAsync(new
                            {
                                type = "audio.test.result",
                                success = true,
                                endpointId,
                                endpointName = endpoint.FriendlyName,
                                frequencyHz = 880,
                                durationMs = 900
                            });
                        }
                        catch (Exception ex)
                        {
                            await SendAsync(new
                            {
                                type = "audio.test.result",
                                success = false,
                                endpointId,
                                endpointName = endpoint.FriendlyName,
                                error = ex.Message
                            });
                        }
                        finally
                        {
                            endpoint.Dispose();
                        }
                        break;
                    }

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

                        var verified = probe.Status == GattCommunicationStatus.Success &&
                                       probe.Services.Count > 0;

                        await SendAsync(new
                        {
                            type = "device.connection",
                            state = verified ? "connected" : "failed",
                            verified,
                            verification = verified ? "uncached-gatt-services" : "uncached-gatt-services-failed",
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


static async Task<string?> ResolveFriendlyNameAsync(ulong address)
{
    using var ble = await BluetoothLEDevice.FromBluetoothAddressAsync(address);
    if (ble is null)
        return null;

    string? best = string.IsNullOrWhiteSpace(ble.Name) ? null : ble.Name.Trim();

    try
    {
        var info = await DeviceInformation.CreateFromIdAsync(
            ble.DeviceId,
            new[]
            {
                "System.ItemNameDisplay",
                "System.Devices.FriendlyName",
                "System.Devices.DeviceInstanceId"
            });

        if (info is not null)
        {
            if (!string.IsNullOrWhiteSpace(info.Name) &&
                (best is null || info.Name.Trim().Length > best.Length))
            {
                best = info.Name.Trim();
            }

            foreach (var key in new[] { "System.Devices.FriendlyName", "System.ItemNameDisplay" })
            {
                if (info.Properties.TryGetValue(key, out var value) &&
                    value is string text &&
                    !string.IsNullOrWhiteSpace(text) &&
                    (best is null || text.Trim().Length > best.Length))
                {
                    best = text.Trim();
                }
            }
        }
    }
    catch
    {
        // Some unpaired devices do not expose all DeviceInformation properties.
    }

    return best;
}


static string? BestDeviceInformationName(DeviceInformation info)
{
    string? best = string.IsNullOrWhiteSpace(info.Name) ? null : info.Name.Trim();

    foreach (var key in new[] { "System.Devices.FriendlyName", "System.ItemNameDisplay" })
    {
        if (info.Properties.TryGetValue(key, out var value) &&
            value is string text &&
            !string.IsNullOrWhiteSpace(text) &&
            (best is null || text.Trim().Length > best.Length))
        {
            best = text.Trim();
        }
    }

    return best;
}
