using System.IO;
using System.Drawing;
using System.Runtime.InteropServices;

namespace YukiCompanion.Windows;

public sealed class WatchedWindowService
{
    public sealed record WindowInfo(nint Handle, string Title, string ProcessName, string Identifier, Rectangle Bounds);
    public sealed record Capture(byte[] Png, WindowInfo Window, Point Cursor, bool CursorInside);

    public IReadOnlyList<WindowInfo> Discover()
    {
        var results = new List<WindowInfo>();
        EnumWindows((handle, _) =>
        {
            if (!IsWindowVisible(handle) || IsIconic(handle)) return true;
            var title = WindowTitle(handle); if (string.IsNullOrWhiteSpace(title)) return true;
            GetWindowThreadProcessId(handle, out var pid);
            try { using var process = System.Diagnostics.Process.GetProcessById((int)pid); var name = process.ProcessName; results.Add(new(handle, title, name, name, Bounds(handle))); }
            catch { /* A window can disappear while being enumerated. */ }
            return true;
        }, nint.Zero);
        return results;
    }

    public WindowInfo? Resolve(WatchedApplication watched)
    {
        return Discover().FirstOrDefault(window =>
            string.Equals(window.ProcessName, watched.Identifier, StringComparison.OrdinalIgnoreCase) &&
            (string.IsNullOrWhiteSpace(watched.WindowIdentifier) || string.Equals(window.Title, watched.WindowIdentifier, StringComparison.OrdinalIgnoreCase)));
    }

    public Capture? CaptureWindow(WindowInfo window)
    {
        if (!IsWindow(window.Handle) || IsIconic(window.Handle)) return null;
        var bounds = Bounds(window.Handle); if (bounds.Width <= 0 || bounds.Height <= 0) return null;
        using var bitmap = new Bitmap(bounds.Width, bounds.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            var dc = graphics.GetHdc(); try { if (!PrintWindow(window.Handle, dc, 2)) return null; } finally { graphics.ReleaseHdc(dc); }
        }
        using var stream = new MemoryStream(); bitmap.Save(stream, System.Drawing.Imaging.ImageFormat.Png);
        GetCursorPos(out var cursor); var relative = new Point(cursor.X - bounds.Left, cursor.Y - bounds.Top);
        return new(stream.ToArray(), window with { Bounds = bounds }, relative, relative.X >= 0 && relative.Y >= 0 && relative.X < bounds.Width && relative.Y < bounds.Height);
    }

    private static string WindowTitle(nint handle) { var length = GetWindowTextLength(handle); var builder = new System.Text.StringBuilder(length + 1); GetWindowText(handle, builder, builder.Capacity); return builder.ToString(); }
    private static Rectangle Bounds(nint handle) { GetWindowRect(handle, out var rect); return new(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top); }
    private delegate bool EnumWindowsProc(nint handle, nint parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, nint parameter);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint handle);
    [DllImport("user32.dll")] private static extern bool IsWindow(nint handle);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint handle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(nint handle, System.Text.StringBuilder text, int maxCount);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(nint handle);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint handle, out uint processId);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint handle, out RECT rect);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] private static extern bool PrintWindow(nint handle, nint hdc, uint flags);
    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
}
