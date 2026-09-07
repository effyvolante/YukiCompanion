using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;

namespace YukiCompanion.Windows;

public partial class CompanionWindow : Window
{
    private readonly CompanionConfiguration configuration;
    private readonly ChromeBridgeClient bridge;
    private readonly WatchedWindowService windows = new();
    private SettingsWindow? settingsWindow;
    public event Action<string>? VisualStateChanged;
    public CompanionWindow(CompanionConfiguration configuration)
    {
        InitializeComponent();
        this.configuration = configuration;
        Icon = new BitmapImage(new Uri(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Yuki", "Idle", "idle_000.png"), UriKind.Absolute));
        bridge = new ChromeBridgeClient();
        Width = Height = Math.Max(260, configuration.Size + 80);
        Title = configuration.CompanionDisplayName;
        CompanionName.Text = configuration.CompanionDisplayName;
        foreach (var message in configuration.Messages.TakeLast(200)) AppendMessage(message.Role, message.Text, persist: false);
        bridge.ReplySubmitted += () => Dispatcher.Invoke(() => { Status.Text = "replying…"; VisualStateChanged?.Invoke("replying"); ActivateWatchedWindow(); });
        bridge.ReplyUpdated += _ => Dispatcher.Invoke(() => { Status.Text = "replying…"; VisualStateChanged?.Invoke("replying"); });
        bridge.ReplyReceived += reply => Dispatcher.Invoke(() => { AppendMessage("yuki", reply); Status.Text = "ready"; VisualStateChanged?.Invoke("answerComplete"); });
        bridge.ErrorReceived += error => Dispatcher.Invoke(() => { AppendMessage("yuki", $"Error: {error}"); Status.Text = "needs attention"; VisualStateChanged?.Invoke("error"); });
        Closed += (_, _) => bridge.Dispose();
    }

    public void ShowChat() { Show(); Activate(); Topmost = true; }
    public void HideChat() => Hide();

    private void Drag(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }
    private async void Send(object sender, RoutedEventArgs e) => await SendMessageAsync();
    private void OpenMenu(object sender, RoutedEventArgs e) { MenuButton.ContextMenu!.IsOpen = true; }
    private void OpenSetup(object sender, RoutedEventArgs e)
    {
        MenuButton.ContextMenu!.IsOpen = false;
        new SetupWindow(configuration) { Owner = this }.ShowDialog();
    }
    private async void CheckForUpdates(object sender, RoutedEventArgs e)
    {
        MenuButton.ContextMenu!.IsOpen = false;
        await UpdateService.CheckAsync(manual: true, this);
    }
    private void OpenFeedback(object sender, RoutedEventArgs e)
    {
        MenuButton.ContextMenu!.IsOpen = false;
        FeedbackService.Open(this);
    }
    private async void Look(object sender, RoutedEventArgs e)
    {
        const string prompt = "What's this?";
        await SendMessageAsync(prompt, includeContext: true);
    }
    private async void ComposerKeyDown(object sender, System.Windows.Input.KeyEventArgs e) { if (e.Key == System.Windows.Input.Key.Enter && System.Windows.Input.Keyboard.Modifiers == ModifierKeys.None) { e.Handled = true; await SendMessageAsync(); } }
    private async Task SendMessageAsync()
    {
        var text = Composer.Text.Trim();
        if (text.Length == 0) return;
        Composer.Clear();
        await SendMessageAsync(text, includeContext: configuration.AutomaticLook && NeedsContext(text));
    }

    private async Task SendMessageAsync(string text, bool includeContext = false)
    {
        AppendMessage("user", text); Status.Text = includeContext ? "looking…" : "thinking…"; VisualStateChanged?.Invoke("thinking");
        LookButton.IsEnabled = false;
        try
        {
            byte[]? image = null;
            var outbound = text;
            if (includeContext)
            {
                if (configuration.WatchedApplication is not { } watched)
                {
                    AppendMessage("yuki", "Choose an open application in Settings before asking Yuki to look."); Status.Text = "needs attention"; VisualStateChanged?.Invoke("error"); return;
                }
                var window = windows.Resolve(watched);
                var capture = window is null ? null : windows.CaptureWindow(window);
                if (capture is null)
                {
                    AppendMessage("yuki", $"I can’t see a visible window for {watched.DisplayName}. Open it and keep a window visible, then try again."); Status.Text = "needs attention"; VisualStateChanged?.Invoke("error"); return;
                }
                image = capture.Png;
                outbound = $"[Full {watched.DisplayName} window attached. Use the entire image as visual context and identify the specific thing described in the user’s question. Cursor position is approximately {Math.Clamp(capture.Cursor.X * 100 / Math.Max(1, capture.Window.Bounds.Width), 0, 100)}% from the left and {Math.Clamp(capture.Cursor.Y * 100 / Math.Max(1, capture.Window.Bounds.Height), 0, 100)}% from the top.]\n{text}";
            }
            await bridge.SendAsync(outbound, image);
        }
        catch (Exception error) { AppendMessage("yuki", $"Error: {error.Message}"); Status.Text = "needs attention"; VisualStateChanged?.Invoke("error"); }
        finally { LookButton.IsEnabled = true; }
    }

    private static bool NeedsContext(string text)
    {
        var value = text.ToLowerInvariant();
        return value.Contains("what's this") || value.Contains("what is this") || value.Contains("look at") || value.Contains("can you see") || value.Contains("screenshot") || value.Contains("on my screen");
    }
    private void OpenSettings(object sender, RoutedEventArgs e)
    {
        settingsWindow ??= new SettingsWindow(configuration);
        settingsWindow.Owner = this;
        settingsWindow.Saved -= SettingsSaved;
        settingsWindow.Saved += SettingsSaved;
        settingsWindow.Closed += (_, _) => settingsWindow = null;
        settingsWindow.Show(); settingsWindow.Activate();
    }

    private void SettingsSaved()
    {
        Title = configuration.CompanionDisplayName;
        CompanionName.Text = configuration.CompanionDisplayName;
        Status.Text = "ready";
    }

    private void AppendMessage(string role, string text, bool persist = true)
    {
        var label = role.Equals("user", StringComparison.OrdinalIgnoreCase) ? "You" : configuration.CompanionDisplayName;
        Transcript.Text += (Transcript.Text.Length == 0 ? "" : "\n\n") + $"{label}: {text}";
        if (persist)
        {
            configuration.Messages.Add(new CompanionMessage { Role = role, Text = text });
            if (configuration.Messages.Count > 200) configuration.Messages = configuration.Messages.TakeLast(200).ToList();
            configuration.Save();
        }
    }

    private void ActivateWatchedWindow()
    {
        if (configuration.WatchedApplication is not { } watched) return;
        if (windows.Resolve(watched) is { } window) SetForegroundWindow(window.Handle);
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint handle);
}
