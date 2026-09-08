using System.Diagnostics;

namespace YukiCompanion.Windows;

public static class BrowserLaunchService
{
    public static void OpenChat(string url, string browser, bool background)
    {
        if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out var target) || target.Scheme != Uri.UriSchemeHttps ||
            (target.Host.ToLowerInvariant() is not ("chatgpt.com" or "chat.openai.com"))) return;
        var executable = browser.ToLowerInvariant() switch
        {
            "chrome" => "chrome.exe",
            "edge" => "msedge.exe",
            _ => target.ToString()
        };
        try
        {
            var process = Process.Start(new ProcessStartInfo { FileName = executable, Arguments = executable.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? $"\"{target}\"" : "", UseShellExecute = true, WindowStyle = background ? ProcessWindowStyle.Minimized : ProcessWindowStyle.Normal });
            if (background && process is not null) _ = Task.Run(async () => { await Task.Delay(700); try { process.Refresh(); if (process.MainWindowHandle != nint.Zero) ShowWindow(process.MainWindowHandle, 6); } catch { } });
        }
        catch { try { Process.Start(new ProcessStartInfo { FileName = target.ToString(), UseShellExecute = true, WindowStyle = background ? ProcessWindowStyle.Minimized : ProcessWindowStyle.Normal }); } catch { } }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool ShowWindow(nint handle, int command);
}
