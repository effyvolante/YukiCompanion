using System.Windows;
using System.Windows.Input;

namespace YukiCompanion.Windows;

public partial class CompanionWindow : Window
{
    private readonly CompanionConfiguration configuration;
    private readonly ChromeBridgeClient bridge = new();
    public CompanionWindow(CompanionConfiguration configuration)
    {
        InitializeComponent();
        this.configuration = configuration;
        Width = Height = configuration.Size + 40;
        Title = configuration.CompanionDisplayName;
        CompanionName.Text = configuration.CompanionDisplayName;
        bridge.ReplyReceived += reply => Dispatcher.Invoke(() => { Transcript.Text += $"\n{configuration.CompanionDisplayName}: {reply}"; });
        bridge.ErrorReceived += error => Dispatcher.Invoke(() => Transcript.Text += $"\nError: {error}");
    }

    private void Drag(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }
    private async void Send(object sender, RoutedEventArgs e) => await SendMessageAsync();
    private async void Look(object sender, RoutedEventArgs e)
    {
        var watched = configuration.WatchedApplication;
        if (watched is null) { System.Windows.MessageBox.Show("Choose a watched window in setup first.", configuration.CompanionDisplayName); return; }
        var window = new WatchedWindowService().Resolve(watched);
        var capture = window is null ? null : new WatchedWindowService().CaptureWindow(window);
        if (capture is null) { Transcript.Text += "\nError: I couldn’t capture the selected window."; return; }
        const string prompt = "What's this?";
        Transcript.Text += $"\nYou: {prompt}";
        await bridge.SendAsync(prompt, capture.Png);
    }
    private async void ComposerKeyDown(object sender, System.Windows.Input.KeyEventArgs e) { if (e.Key == System.Windows.Input.Key.Enter && System.Windows.Input.Keyboard.Modifiers == ModifierKeys.None) { e.Handled = true; await SendMessageAsync(); } }
    private async Task SendMessageAsync()
    {
        var text = Composer.Text.Trim();
        if (text.Length == 0) return;
        Composer.Clear();
        Transcript.Text += $"\nYou: {text}";
        try { await bridge.SendAsync(text); } catch (Exception error) { Transcript.Text += $"\nError: {error.Message}"; }
    }
    private void OpenSettings(object sender, RoutedEventArgs e) => System.Windows.MessageBox.Show("Settings and setup will use your saved companion configuration.", configuration.CompanionDisplayName);
}
