using System.Diagnostics;
using System.Drawing;
using System.Net.Sockets;
using System.Text;
using System.Windows.Forms;
using NAudio.CoreAudioApi;

internal sealed class TrayApp : IDisposable
{
    private readonly Thread _uiThread;
    private readonly ManualResetEventSlim _ready = new(false);
    private NotifyIcon? _notifyIcon;
    private Form? _form;
    private Label? _hostStatus;
    private Label? _wsaStatus;
    private Label? _daemonStatus;
    private Label? _audioStatus;
    private Label? _portsStatus;
    private System.Windows.Forms.Timer? _timer;
    private bool _disposed;

    private readonly bool _showInitially;

    private TrayApp(bool showInitially)
    {
        _showInitially = showInitially;
        _uiThread = new Thread(UiMain)
        {
            IsBackground = true,
            Name = "wsa-bt-tray"
        };
        _uiThread.SetApartmentState(ApartmentState.STA);
        _uiThread.Start();
        _ready.Wait(TimeSpan.FromSeconds(5));
    }

    public static TrayApp Start(bool showInitially = false) => new(showInitially);

    private void UiMain()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        _notifyIcon = new NotifyIcon
        {
            Text = "WSA Bluetooth Bridge",
            Icon = SystemIcons.Information,
            Visible = true
        };

        var menu = new ContextMenuStrip();
        menu.Items.Add("פתח סטטוס", null, (_, _) => ShowWindow());
        menu.Items.Add("בדוק עכשיו", null, async (_, _) => await RefreshStatusAsync());
        menu.Items.Add("תקן / התקן רכיב WSA", null, (_, _) => RunRepair());
        menu.Items.Add("פתח תיקיית לוגים", null, (_, _) => OpenLogs());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("הפעל מחדש", null, (_, _) => RestartBridge());
        menu.Items.Add("יציאה", null, (_, _) => Environment.Exit(0));
        _notifyIcon.ContextMenuStrip = menu;
        _notifyIcon.DoubleClick += (_, _) => ShowWindow();

        _form = BuildStatusForm();
        if (_showInitially)
            _form.Shown += (_, _) => _ = RefreshStatusAsync();
        else
            _form.Load += (_, _) => _form.Hide();

        _timer = new System.Windows.Forms.Timer { Interval = 4000 };
        _timer.Tick += async (_, _) => await RefreshStatusAsync();
        _timer.Start();

        _ready.Set();
        _ = RefreshStatusAsync();
        Application.Run();
    }

    private Form BuildStatusForm()
    {
        var form = new Form
        {
            Text = "WSA Bluetooth Bridge",
            Width = 560,
            Height = 430,
            StartPosition = FormStartPosition.CenterScreen,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = true,
            RightToLeft = RightToLeft.Yes,
            RightToLeftLayout = true
        };

        form.FormClosing += (_, e) =>
        {
            if (!_disposed)
            {
                e.Cancel = true;
                form.Hide();
            }
        };

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(18),
            ColumnCount = 1,
            RowCount = 8,
            AutoSize = true,
            RightToLeft = RightToLeft.Yes
        };

        var title = new Label
        {
            Text = "WSA Bluetooth Bridge",
            Dock = DockStyle.Fill,
            AutoSize = true,
            Font = new Font(SystemFonts.MessageBoxFont.FontFamily, 16, FontStyle.Bold),
            TextAlign = ContentAlignment.MiddleCenter,
            Padding = new Padding(0, 0, 0, 12)
        };

        _hostStatus = NewStatusLabel("Windows Host: בודק...");
        _wsaStatus = NewStatusLabel("WSA: בודק...");
        _daemonStatus = NewStatusLabel("Android daemon: בודק...");
        _audioStatus = NewStatusLabel("אודיו: בודק...");
        _portsStatus = NewStatusLabel("פורטים: בודק...");

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            WrapContents = true,
            Padding = new Padding(0, 14, 0, 0)
        };

        buttons.Controls.Add(NewButton("בדוק עכשיו", async (_, _) => await RefreshStatusAsync()));
        buttons.Controls.Add(NewButton("תקן רכיב WSA", (_, _) => RunRepair()));
        buttons.Controls.Add(NewButton("פתח לוגים", (_, _) => OpenLogs()));
        buttons.Controls.Add(NewButton("הפעל מחדש", (_, _) => RestartBridge()));

        var hint = new Label
        {
            Text = "המערכת ממשיכה לרוץ גם כשהחלון סגור. לפתיחה מחדש: לחץ פעמיים על הסמל ליד השעון.",
            Dock = DockStyle.Fill,
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Padding = new Padding(0, 18, 0, 0)
        };

        root.Controls.Add(title);
        root.Controls.Add(_hostStatus);
        root.Controls.Add(_wsaStatus);
        root.Controls.Add(_daemonStatus);
        root.Controls.Add(_audioStatus);
        root.Controls.Add(_portsStatus);
        root.Controls.Add(buttons);
        root.Controls.Add(hint);
        form.Controls.Add(root);

        return form;
    }

    private static Label NewStatusLabel(string text) => new()
    {
        Text = text,
        Dock = DockStyle.Fill,
        AutoSize = true,
        Font = new Font(SystemFonts.MessageBoxFont.FontFamily, 10.5f),
        Padding = new Padding(8, 8, 8, 8),
        BorderStyle = BorderStyle.FixedSingle
    };

    private static Button NewButton(string text, EventHandler onClick)
    {
        var button = new Button
        {
            Text = text,
            AutoSize = true,
            Padding = new Padding(10, 4, 10, 4),
            Margin = new Padding(5)
        };
        button.Click += onClick;
        return button;
    }

    private void ShowWindow()
    {
        if (_form is null) return;
        _form.Show();
        _form.WindowState = FormWindowState.Normal;
        _form.BringToFront();
        _form.Activate();
    }

    private async Task RefreshStatusAsync()
    {
        if (_form is null || _form.IsDisposed) return;

        var port17890 = await CanConnectAsync(17890);
        var port17891 = await CanConnectAsync(17891);

        var adb = LocateAdb();
        var wsaText = "לא מחובר";
        var daemonText = "לא ידוע";

        if (adb is not null)
        {
            try
            {
                var devices = await RunProcessAsync(adb, "devices");
                var serial = ParseFirstOnlineDevice(devices);
                if (serial is not null)
                {
                    wsaText = "מחובר (" + serial + ")";
                    var daemon = await RunProcessAsync(adb, $"-s \"{serial}\" shell sh -c \"pidof wsa-btd || pgrep wsa-btd\"");
                    daemonText = string.IsNullOrWhiteSpace(daemon) ? "לא פעיל" : "פעיל";
                }
            }
            catch
            {
                wsaText = "ADB אינו זמין";
            }
        }
        else
        {
            wsaText = "ADB לא נמצא";
        }

        var audioText = "לא נמצאה יציאת שמע";
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            using var render = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            using var capture = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Communications);
            audioText = $"פלט: {render.FriendlyName} | מיקרופון: {capture.FriendlyName}";
        }
        catch
        {
        }

        void Apply()
        {
            if (_hostStatus is null) return;
            _hostStatus.Text = "Windows Host: ✅ פעיל";
            _wsaStatus!.Text = "WSA: " + (wsaText.StartsWith("מחובר") ? "✅ " : "⚠️ ") + wsaText;
            _daemonStatus!.Text = "Android daemon: " + (daemonText == "פעיל" ? "✅ פעיל" : "⚠️ " + daemonText);
            _audioStatus!.Text = "אודיו: " + audioText;
            _portsStatus!.Text = $"פורטים: {(port17890 ? "✅" : "❌")} 17890   {(port17891 ? "✅" : "❌")} 17891";

            if (_notifyIcon is not null)
                _notifyIcon.Text = wsaText.StartsWith("מחובר")
                    ? "WSA Bluetooth Bridge - מחובר"
                    : "WSA Bluetooth Bridge - ממתין ל-WSA";
        }

        if (_form.InvokeRequired)
            _form.BeginInvoke((Action)Apply);
        else
            Apply();
    }

    private static async Task<bool> CanConnectAsync(int port)
    {
        try
        {
            using var client = new TcpClient();
            using var timeout = new CancellationTokenSource(600);
            await client.ConnectAsync("127.0.0.1", port, timeout.Token);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string? LocateAdb()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "platform-tools", "adb.exe"),
            Path.Combine(AppContext.BaseDirectory, "adb.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Android", "Sdk", "platform-tools", "adb.exe")
        };

        return candidates.FirstOrDefault(File.Exists);
    }

    private static string? ParseFirstOnlineDevice(string text)
    {
        foreach (var line in text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = line.Trim().Split(new[] { '\t', ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 2 && parts[1] == "device")
                return parts[0];
        }
        return null;
    }

    private static async Task<string> RunProcessAsync(string file, string arguments)
    {
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = file,
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        }) ?? throw new InvalidOperationException("Unable to start process.");

        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        return (await stdout).Trim();
    }

    private static void RunRepair()
    {
        var script = Path.Combine(AppContext.BaseDirectory, "Install-WsaSystem.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("קובץ התיקון Install-WsaSystem.ps1 לא נמצא.", "WSA Bluetooth Bridge");
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-ExecutionPolicy Bypass -NoProfile -File \"{script}\"",
            UseShellExecute = true,
            Verb = "runas"
        });
    }

    private static void OpenLogs()
    {
        var folder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WSABluetoothBridge");
        Directory.CreateDirectory(folder);
        Process.Start(new ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments = $"\"{folder}\"",
            UseShellExecute = true
        });
    }

    private static void RestartBridge()
    {
        var exe = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(exe)) return;

        var command = $"/c timeout /t 2 /nobreak >nul & start \"\" \"{exe}\" --background";
        Process.Start(new ProcessStartInfo("cmd.exe", command)
        {
            UseShellExecute = false,
            CreateNoWindow = true
        });

        Environment.Exit(0);
    }

    public void Dispose()
    {
        _disposed = true;

        if (_form is not null && !_form.IsDisposed)
        {
            try
            {
                _form.BeginInvoke(() =>
                {
                    _timer?.Stop();
                    if (_notifyIcon is not null)
                    {
                        _notifyIcon.Visible = false;
                        _notifyIcon.Dispose();
                    }
                    _form.Close();
                    Application.ExitThread();
                });
            }
            catch
            {
            }
        }

        _ready.Dispose();
    }
}
