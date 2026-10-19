using System.Diagnostics;
using System.Runtime.InteropServices;
using System.ComponentModel;
using System.Windows.Forms;

namespace FastSwitch.Tray;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(initiallyOwned: true, "Local\\FastSwitch.Tray", out var firstInstance);
        if (!firstInstance)
            return;

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplicationContext());
    }
}

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _switchMenuItem;
    private readonly ToolStripMenuItem _exitMenuItem;
    private readonly HotkeyWindow _hotkeyWindow;
    private bool _switchInProgress;

    public TrayApplicationContext()
    {
        _switchMenuItem = new ToolStripMenuItem("切换到 Mac（Ctrl+Alt+M）");
        _switchMenuItem.Click += async (_, _) => await SwitchToMacAsync();
        _exitMenuItem = new ToolStripMenuItem("退出 FastSwitch", null, (_, _) => ExitThread());

        var menu = new ContextMenuStrip();
        menu.Items.Add(_switchMenuItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_exitMenuItem);

        _icon = new NotifyIcon
        {
            Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application,
            Text = "FastSwitch：Ctrl+Alt+M 切换到 Mac",
            ContextMenuStrip = menu,
            Visible = true
        };

        _hotkeyWindow = new HotkeyWindow(() => _ = SwitchToMacAsync());
        if (_hotkeyWindow.IsRegistered)
        {
            _icon.ShowBalloonTip(3000, "FastSwitch 已在后台运行", "按 Ctrl+Alt+M 切换到 Mac。", ToolTipIcon.Info);
        }
        else
        {
            _icon.ShowBalloonTip(5000, "快捷键不可用", "Ctrl+Alt+M 可能已被其他程序占用；仍可从托盘菜单切换。", ToolTipIcon.Warning);
        }
    }

    private async Task SwitchToMacAsync()
    {
        if (_switchInProgress)
        {
            _icon.ShowBalloonTip(2000, "FastSwitch 正在切换", "请等待当前切换完成。", ToolTipIcon.Info);
            return;
        }

        _switchInProgress = true;
        _switchMenuItem.Enabled = false;
        _exitMenuItem.Enabled = false;
        var internalModeEnabled = false;
        try
        {
            _icon.Text = "FastSwitch：正在切换到 Mac";
            // The original working script does not abort when a DDC write is
            // rejected. It immediately disables the Windows HDMI output so
            // the monitor can auto-select the Mac input, then restores HDMI
            // after the Mac signal has stabilized.
            var ddcWarning = await Task.Run(MonitorInput.SelectUsbC);

            await RunDisplaySwitchAsync("/internal");
            internalModeEnabled = true;
            await Task.Delay(TimeSpan.FromSeconds(2));

            for (var seconds = 12; seconds >= 1; seconds--)
            {
                _icon.Text = $"FastSwitch：等待 Mac 启动 {seconds}s";
                await Task.Delay(TimeSpan.FromSeconds(1));
            }

            await RunDisplaySwitchAsync("/extend");
            internalModeEnabled = false;
            await Task.Delay(TimeSpan.FromSeconds(2));
            _icon.Text = "FastSwitch：Ctrl+Alt+M 切换到 Mac";
            if (string.IsNullOrEmpty(ddcWarning))
            {
                _icon.ShowBalloonTip(3000, "已切换到 Mac", "Windows HDMI 输出已恢复，可从 Mac 切回。", ToolTipIcon.Info);
            }
            else
            {
                _icon.ShowBalloonTip(6000, "切换流程已完成（DDC/CI 未确认）",
                    "DDC/CI 返回错误 31。请在显示器 OSD 设置 Extra > DDC/CI = Yes、Input Select = Auto，并确认 Windows HDMI 与 Mac USB-C 均已连接。",
                    ToolTipIcon.Warning);
            }
        }
        catch (Exception ex)
        {
            var errorMessage = ex.Message;
            if (internalModeEnabled)
            {
                try
                {
                    await RunDisplaySwitchAsync("/extend");
                }
                catch (Exception restoreError)
                {
                    errorMessage = $"{errorMessage} HDMI 恢复也失败：{restoreError.Message}";
                }
            }
            _icon.Text = "FastSwitch：切换失败";
            _icon.ShowBalloonTip(6000, "切换失败", errorMessage, ToolTipIcon.Error);
        }
        finally
        {
            _switchInProgress = false;
            _switchMenuItem.Enabled = true;
            _exitMenuItem.Enabled = true;
            if (_icon.Text.StartsWith("FastSwitch：切换失败", StringComparison.Ordinal))
                _icon.Text = "FastSwitch：Ctrl+Alt+M 切换到 Mac";
        }
    }

    private static async Task RunDisplaySwitchAsync(string argument)
    {
        var executable = Path.Combine(Environment.SystemDirectory, "DisplaySwitch.exe");
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = executable,
            Arguments = argument,
            UseShellExecute = false,
            CreateNoWindow = true
        }) ?? throw new InvalidOperationException("无法启动 Windows DisplaySwitch.exe。");

        await process.WaitForExitAsync();
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"DisplaySwitch.exe {argument} 失败（退出码 {process.ExitCode}）。");
    }

    protected override void ExitThreadCore()
    {
        _hotkeyWindow.Dispose();
        _icon.Visible = false;
        _icon.Dispose();
        base.ExitThreadCore();
    }
}

internal sealed class HotkeyWindow : NativeWindow, IDisposable
{
    private const int HotkeyId = 0x4653;
    private const int WmHotkey = 0x0312;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModNoRepeat = 0x4000;
    private const uint VirtualKeyM = 0x4D;
    private readonly Action _onHotkey;

    public bool IsRegistered { get; }

    public HotkeyWindow(Action onHotkey)
    {
        _onHotkey = onHotkey;
        CreateHandle(new CreateParams());
        IsRegistered = RegisterHotKey(Handle, HotkeyId, ModAlt | ModControl | ModNoRepeat, VirtualKeyM);
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == WmHotkey && message.WParam.ToInt32() == HotkeyId)
            _onHotkey();
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        if (IsRegistered)
            UnregisterHotKey(Handle, HotkeyId);
        DestroyHandle();
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}

internal static class MonitorInput
{
    private const byte InputSelectVcpCode = 0x60;
    private const uint UsbCInputValue = 27;

    public static string? SelectUsbC()
    {
        var failures = new List<string>();
        var successCount = 0;
        var physicalMonitorCount = 0;
        MonitorEnumProc callback = (IntPtr monitor, IntPtr hdc, ref Rect rect, IntPtr data) =>
        {
            // Match the original PowerShell script: open, use, and destroy each
            // physical-monitor handle inside the HMONITOR enumeration callback.
            // Keeping these handles until EnumDisplayMonitors returns can make
            // DDC/CI operations fail on some display drivers.
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out var count) || count == 0)
                return true;

            var physicalMonitors = new PhysicalMonitor[count];
            if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physicalMonitors))
                return true;

            try
            {
                physicalMonitorCount += physicalMonitors.Length;
                foreach (var physicalMonitor in physicalMonitors)
                {
                    if (SetVCPFeature(physicalMonitor.Handle, InputSelectVcpCode, UsbCInputValue))
                    {
                        successCount++;
                    }
                    else
                    {
                        failures.Add($"{physicalMonitor.Description}: DDC/CI 错误 {Marshal.GetLastWin32Error()}");
                    }
                }
            }
            finally
            {
                DestroyPhysicalMonitors(count, physicalMonitors);
            }

            return true;
        };

        if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法枚举 Windows 显示器。");

        if (successCount == 0)
        {
            var detail = physicalMonitorCount == 0
                ? "没有打开任何 DDC 物理显示器句柄"
                : string.Join("；", failures);
            return $"DDC/CI 没有确认 USB-C 命令：{detail}。";
        }

        return null;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PhysicalMonitor
    {
        public IntPtr Handle;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string Description;
    }

    private delegate bool MonitorEnumProc(IntPtr monitor, IntPtr hdc, ref Rect rect, IntPtr data);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc callback, IntPtr data);

    [DllImport("dxva2.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor, out uint count);

    [DllImport("dxva2.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor, uint count, [Out] PhysicalMonitor[] physicalMonitors);

    [DllImport("dxva2.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyPhysicalMonitors(uint count, [In] PhysicalMonitor[] physicalMonitors);

    [DllImport("dxva2.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetVCPFeature(IntPtr monitor, byte code, uint value);
}
