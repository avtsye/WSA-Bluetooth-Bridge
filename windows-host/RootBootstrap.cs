using System.Diagnostics;
using System.Text;

internal enum RootBootstrapResult
{
    AlreadyRooted,
    UpgradeSucceeded,
    UpgradeFailed,
    Skipped
}

internal static class RootBootstrap
{
    public static async Task<RootBootstrapResult> EnsureAsync()
    {
        var common = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        var logDir = Path.Combine(common, "WSABluetoothBridge");
        Directory.CreateDirectory(logDir);

        var logFile = Path.Combine(logDir, "root-bootstrap.log");
        var marker = Path.Combine(logDir, "root-bootstrap-invoked.txt");

        await File.AppendAllTextAsync(
            marker,
            $"Bootstrap invoked: {DateTime.Now:yyyy-MM-dd HH:mm:ss}{Environment.NewLine}",
            Encoding.UTF8);

        try
        {
            var adb = LocateAdb();
            if (adb is null)
            {
                await LogAsync(logFile, "ADB not found; root bootstrap skipped.");
                return RootBootstrapResult.Skipped;
            }

            var serial = await FindWsaAsync(adb);
            if (serial is null)
            {
                await LogAsync(logFile, "WSA not connected in ADB; root bootstrap skipped.");
                return RootBootstrapResult.Skipped;
            }

            var root = await RunAsync(adb, $"-s \"{serial}\" shell su -c id");
            if (root.ExitCode == 0 && root.Output.Contains("uid=0", StringComparison.Ordinal))
            {
                await LogAsync(logFile, "Root already available.");
                return RootBootstrapResult.AlreadyRooted;
            }

            var upgrade = Path.Combine(AppContext.BaseDirectory, "Upgrade-Wsa.ps1");
            if (!File.Exists(upgrade))
            {
                await LogAsync(logFile, "Upgrade-Wsa.ps1 not found.");
                return RootBootstrapResult.UpgradeFailed;
            }

            await LogAsync(logFile, "Root missing. Launching elevated Upgrade-Wsa.ps1 -ForceRoot.");

            var wrapper = Path.Combine(AppContext.BaseDirectory, "Run-RootUpgrade.cmd");
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = File.Exists(wrapper) ? wrapper : "powershell.exe",
                Arguments = File.Exists(wrapper)
                    ? ""
                    : $"-ExecutionPolicy Bypass -NoProfile -File \"{upgrade}\" -ForceRoot",
                WorkingDirectory = AppContext.BaseDirectory,
                UseShellExecute = true,
                Verb = "runas"
            });

            if (process is null)
            {
                await LogAsync(logFile, "Failed to launch elevated upgrade process.");
                return RootBootstrapResult.UpgradeFailed;
            }

            await process.WaitForExitAsync();
            await LogAsync(logFile, $"Elevated upgrade process exited with {process.ExitCode}.");

            if (process.ExitCode != 0)
                return RootBootstrapResult.UpgradeFailed;

            serial = await FindWsaAsync(adb, 180);
            if (serial is null)
            {
                await LogAsync(logFile, "WSA did not return to ADB after root upgrade.");
                return RootBootstrapResult.UpgradeFailed;
            }

            root = await RunAsync(adb, $"-s \"{serial}\" shell su -c id");
            var ok = root.ExitCode == 0 && root.Output.Contains("uid=0", StringComparison.Ordinal);
            await LogAsync(logFile, ok ? "Root verification passed." : "Root verification failed after upgrade.");
            return ok ? RootBootstrapResult.UpgradeSucceeded : RootBootstrapResult.UpgradeFailed;
        }
        catch (Exception ex)
        {
            await LogAsync(logFile, "Bootstrap exception: " + ex);
            return RootBootstrapResult.UpgradeFailed;
        }
    }

    private static string? LocateAdb()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "platform-tools", "adb.exe"),
            Path.Combine(AppContext.BaseDirectory, "adb.exe")
        };

        return candidates.FirstOrDefault(File.Exists);
    }

    private static async Task<string?> FindWsaAsync(string adb, int timeoutSeconds = 15)
    {
        await RunAsync(adb, "start-server");
        await RunAsync(adb, "connect 127.0.0.1:58526");

        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (DateTime.UtcNow < deadline)
        {
            var devices = await RunAsync(adb, "devices");
            foreach (var line in devices.Output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var parts = line.Trim().Split(new[] { '\t', ' ' }, StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length >= 2 && parts[1] == "device" &&
                    (parts[0].StartsWith("127.0.0.1:", StringComparison.OrdinalIgnoreCase) ||
                     parts[0].StartsWith("localhost:", StringComparison.OrdinalIgnoreCase)))
                    return parts[0];
            }

            await Task.Delay(2000);
        }

        return null;
    }

    private static async Task<(int ExitCode, string Output)> RunAsync(string file, string arguments)
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = file,
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        }) ?? throw new InvalidOperationException("Failed to start " + file);

        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        return (process.ExitCode, ((await stdout) + Environment.NewLine + (await stderr)).Trim());
    }

    private static Task LogAsync(string path, string line) =>
        File.AppendAllTextAsync(path, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {line}{Environment.NewLine}", Encoding.UTF8);
}
