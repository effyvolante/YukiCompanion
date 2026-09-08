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
    public event Action<string>? ThemeChanged;
    public string ThemeId => configuration.ThemeId;
    public CompanionWindow(CompanionConfiguration configuration)
    {
        InitializeComponent();
        this.configuration = configuration;
        Icon = new BitmapImage(new Uri(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Yuki", "Idle", "idle_000.png"), UriKind.Absolute));
        bridge = new ChromeBridgeClient();
        Width = Height = Math.Max(260, configuration.Size + 80);
        Title = configuration.CompanionDisplayName;
        CompanionName.Text = configuration.CompanionDisplayName;
        Composer.Text = configuration.Draft;
        RenderTranscript();
        bridge.ReplySubmitted += _ => Dispatcher.Invoke(() => { Status.Text = "Yuki is replying…"; VisualStateChanged?.Invoke("replying"); });
        bridge.ReplyUpdated += (id, text) => Dispatcher.Invoke(() => { UpdateStreamingResponse(id, text); Status.Text = "Yuki is replying…"; VisualStateChanged?.Invoke("replying"); });
        bridge.ReplyReceived += (id, reply) => Dispatcher.Invoke(() => { CompleteStreamingResponse(id, reply); Status.Text = "Ready"; VisualStateChanged?.Invoke("answerComplete"); });
        bridge.PhaseChanged += (id, phase) => Dispatcher.Invoke(() => UpdateDelivery(id, phase));
        bridge.ErrorReceived += (id, error) => Dispatcher.Invoke(() => { UpdateDelivery(id, "failed"); AppendMessage("yuki", error); Status.Text = "Needs attention"; VisualStateChanged?.Invoke("error"); });
        bridge.ConnectionStateChanged += state => Dispatcher.Invoke(() => Status.Text = state == "ready" ? "Ready" : state == "needs_binding" ? "Needs extension" : "Connecting…");
        Closed += (_, _) => bridge.Dispose();
    }

    public void ShowChat() { Show(); Activate(); Topmost = true; }
    public void HideChat() => Hide();

    private void Drag(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }
    private async void Send(object sender, RoutedEventArgs e) => await SendMessageAsync();
    private void OpenMenu(object sender, RoutedEventArgs e) { MenuButton.ContextMenu!.IsOpen = true; }
    private void ReconnectChatGPT(object sender, RoutedEventArgs e) { MenuButton.ContextMenu!.IsOpen = false; Status.Text = "Connecting…"; bridge.Reconnect(); }
    private void RetryLastMessage(object sender, RoutedEventArgs e)
    {
        MenuButton.ContextMenu!.IsOpen = false;
        var message = configuration.Messages.LastOrDefault(value => value.Role.Equals("user", StringComparison.OrdinalIgnoreCase) && value.DeliveryState == "failed");
        if (message is null) { Status.Text = "Nothing to retry"; return; }
        Composer.Text = message.Text;
        Composer.CaretIndex = Composer.Text.Length;
        Composer.Focus();
    }
    private void CloseChat(object sender, RoutedEventArgs e) { Close(); System.Windows.Application.Current.Shutdown(); }
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
    private void ComposerTextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        if (configuration is null) return;
        configuration.Draft = Composer.Text;
        configuration.Save();
    }
    private async Task SendMessageAsync()
    {
        var text = Composer.Text.Trim();
        if (text.Length == 0) return;
        Composer.Clear();
        await SendMessageAsync(text, includeContext: configuration.AutomaticLook && NeedsContext(text));
    }

    private async Task SendMessageAsync(string text, bool includeContext = false)
    {
        var messageId = Guid.NewGuid().ToString();
        AppendMessage("user", text, id: messageId, deliveryState: "queued"); Status.Text = includeContext ? "Looking…" : "Connecting…"; VisualStateChanged?.Invoke("thinking");
        LookButton.IsEnabled = false;
        try
        {
            byte[]? image = null;
            var outbound = text;
            if (includeContext)
            {
                if (configuration.WatchedApplication is not { } watched)
                {
                    UpdateDelivery(messageId, "failed");
                    AppendMessage("yuki", "Choose an open application in Settings before asking Yuki to look."); Status.Text = "needs attention"; VisualStateChanged?.Invoke("error"); return;
                }
                var window = windows.Resolve(watched);
                var capture = window is null ? null : windows.CaptureWindow(window);
                if (capture is null)
                {
                    UpdateDelivery(messageId, "failed");
                    AppendMessage("yuki", $"I can’t see a visible window for {watched.DisplayName}. Open it and keep a window visible, then try again."); Status.Text = "needs attention"; VisualStateChanged?.Invoke("error"); return;
                }
                image = capture.Png;
                outbound = $"[Full {watched.DisplayName} window attached. Use the entire image as visual context and identify the specific thing described in the user’s question. Cursor position is approximately {Math.Clamp(capture.Cursor.X * 100 / Math.Max(1, capture.Window.Bounds.Width), 0, 100)}% from the left and {Math.Clamp(capture.Cursor.Y * 100 / Math.Max(1, capture.Window.Bounds.Height), 0, 100)}% from the top.]\n{text}";
            }
            await bridge.SendAsync(messageId, outbound, image);
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
        ThemeChanged?.Invoke(configuration.ThemeId);
    }

    private void AppendMessage(string role, string text, bool persist = true, string? id = null, string? deliveryState = null)
    {
        if (persist)
        {
            configuration.Messages.Add(new CompanionMessage { Id = id ?? Guid.NewGuid().ToString(), Role = role, Text = text, DeliveryState = deliveryState });
            if (configuration.Messages.Count > 200) configuration.Messages = configuration.Messages.TakeLast(200).ToList();
            configuration.Save();
        }
        RenderTranscript();
    }

    private void UpdateDelivery(string id, string phase)
    {
        var message = configuration.Messages.FirstOrDefault(value => value.Id == id);
        if (message is null) return;
        message.DeliveryState = phase;
        configuration.Save();
        RenderTranscript();
    }

    private void UpdateStreamingResponse(string commandId, string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        var responseId = $"response-{commandId}";
        var message = configuration.Messages.FirstOrDefault(value => value.Id == responseId);
        if (message is null) configuration.Messages.Add(new CompanionMessage { Id = responseId, Role = "yuki", Text = text, DeliveryState = "responding" });
        else { message.Text = text; message.DeliveryState = "responding"; }
        configuration.Save();
        RenderTranscript();
    }

    private void CompleteStreamingResponse(string commandId, string text)
    {
        UpdateDelivery(commandId, "completed");
        var responseId = $"response-{commandId}";
        var message = configuration.Messages.FirstOrDefault(value => value.Id == responseId);
        if (message is null) configuration.Messages.Add(new CompanionMessage { Id = responseId, Role = "yuki", Text = text, DeliveryState = "completed" });
        else { message.Text = text; message.DeliveryState = "completed"; }
        configuration.Save();
        RenderTranscript();
    }

    private void RenderTranscript()
    {
        var followLatest = TranscriptScroller.ScrollableHeight - TranscriptScroller.VerticalOffset < 24;
        Transcript.Text = string.Join("\n\n", configuration.Messages.TakeLast(200).Select(message =>
        {
            var label = message.Role.Equals("user", StringComparison.OrdinalIgnoreCase) ? "You" : configuration.CompanionDisplayName;
            var state = message.Role.Equals("user", StringComparison.OrdinalIgnoreCase) && message.DeliveryState is not null and not "completed" ? $"\n{DeliveryLabel(message.DeliveryState)}" : "";
            return $"{label}: {message.Text}{state}";
        }));
        if (followLatest) Dispatcher.BeginInvoke(TranscriptScroller.ScrollToEnd);
    }

    private static string DeliveryLabel(string state) => state switch
    {
        "queued" => "Sending…",
        "delivered" => "Delivered",
        "submitted" => "Sent",
        "responding" => "Yuki is replying…",
        "failed" => "Needs attention",
        _ => ""
    };

}
