using System.Diagnostics;

internal sealed class AdbReverseManager : IDisposable
{
    private readonly int[] _ports;
    private readonly CancellationTokenSource _stop = new();
    private Task? _worker;

    public AdbReverseManager(params int[] ports)
    {
        _ports = ports;
    }

    public void Start()
    {
        if (_worker is not null) return;
        _worker = Task.Run(() => RunAsync(_stop.Token));
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        var adb = FindAdb();
        if (adb is null)
        {
            Console.Error.WriteLine("ADB was not found. The packaged build should contain platform-tools\\adb.exe.");
            return;
        }

        Console.WriteLine($"ADB: {adb}");

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                var devicesText = await RunAdbAsync(adb, "devices", cancellationToken);
                var devices = ParseDevices(devicesText);

                if (devices.Count == 0)
                {
                    foreach (var endpoint in new[] { "127.0.0.1:58526", "localhost:58526" })
                    {
                        try
                        {
                            await RunAdbAsync(adb, $"connect {endpoint}", cancellationToken);
                        }
                        catch
                        {
                        }
                    }

                    devicesText = await RunAdbAsync(adb, "devices", cancellationToken);
                    devices = ParseDevices(devicesText);
                }

                if (devices.Count == 0)
                {
                    Console.WriteLine("Waiting for WSA/ADB device...");
                }
                else
                {
                    foreach (var serial in PickTargets(devices))
                    {
                        var allOk = true;
                        foreach (var port in _ports)
                        {
                            var result = await RunAdbAsync(
                                adb,
                                $"-s \"{serial}\" reverse tcp:{port} tcp:{port}",
                                cancellationToken);

                            if (!result.Contains(port.ToString(), StringComparison.OrdinalIgnoreCase) &&
                                !string.IsNullOrWhiteSpace(result))
                            {
                                // adb reverse commonly prints the local endpoint; empty output can
                                // also mean success on some versions.
                            }
                        }

                        if (allOk)
                        {
                            Console.WriteLine(
                                $"WSA ADB forwarding ready for {serial}: " +
                                string.Join(", ", _ports.Select(x => $"tcp:{x}")));
                        }
                    }
                }
            }
            catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
            {
                Console.Error.WriteLine($"Automatic ADB reverse failed: {ex.Message}");
            }

            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private static string? FindAdb()
    {
        var baseDir = AppContext.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(baseDir, "platform-tools", "adb.exe"),
            Path.Combine(baseDir, "adb.exe"),
            Environment.GetEnvironmentVariable("ANDROID_HOME") is string ah
                ? Path.Combine(ah, "platform-tools", "adb.exe")
                : null,
            Environment.GetEnvironmentVariable("ANDROID_SDK_ROOT") is string ar
                ? Path.Combine(ar, "platform-tools", "adb.exe")
                : null,
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Android", "Sdk", "platform-tools", "adb.exe")
        };

        foreach (var candidate in candidates)
        {
            if (!string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate))
                return candidate;
        }

        try
        {
            using var p = Process.Start(new ProcessStartInfo
            {
                FileName = "where.exe",
                Arguments = "adb.exe",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            });

            if (p is not null)
            {
                var first = p.StandardOutput.ReadLine();
                p.WaitForExit(2000);
                if (!string.IsNullOrWhiteSpace(first) && File.Exists(first.Trim()))
                    return first.Trim();
            }
        }
        catch
        {
        }

        return null;
    }

    private static async Task<string> RunAdbAsync(
        string adb,
        string arguments,
        CancellationToken cancellationToken)
    {
        var psi = new ProcessStartInfo
        {
            FileName = adb,
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException("Unable to start adb.exe.");

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);

        await process.WaitForExitAsync(cancellationToken);
        var stdout = await stdoutTask;
        var stderr = await stderrTask;

        if (process.ExitCode != 0)
            throw new InvalidOperationException(
                $"adb {arguments} failed ({process.ExitCode}): {stderr.Trim()}");

        return string.IsNullOrWhiteSpace(stdout) ? stderr.Trim() : stdout.Trim();
    }

    private static List<string> ParseDevices(string text)
    {
        var result = new List<string>();

        foreach (var raw in text.Split(new[] { '\r', '\n' },
                     StringSplitOptions.RemoveEmptyEntries))
        {
            var line = raw.Trim();
            if (line.StartsWith("List of devices", StringComparison.OrdinalIgnoreCase))
                continue;

            var parts = line.Split(new[] { '\t', ' ' },
                StringSplitOptions.RemoveEmptyEntries);

            if (parts.Length >= 2 &&
                string.Equals(parts[1], "device", StringComparison.OrdinalIgnoreCase))
            {
                result.Add(parts[0]);
            }
        }

        return result;
    }

    private static IEnumerable<string> PickTargets(List<string> devices)
    {
        if (devices.Count == 1)
            return devices;

        var network = devices
            .Where(x => x.Contains(':') ||
                        x.StartsWith("127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
                        x.StartsWith("localhost", StringComparison.OrdinalIgnoreCase))
            .ToArray();

        return network.Length > 0 ? network : devices;
    }

    public void Dispose()
    {
        _stop.Cancel();
        try { _worker?.Wait(1000); } catch { }
        _stop.Dispose();
    }
}
