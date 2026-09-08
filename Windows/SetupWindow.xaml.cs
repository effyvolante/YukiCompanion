using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;

namespace YukiCompanion.Windows;

public partial class SetupWindow : Window
{
    private readonly CompanionConfiguration configuration;
    private readonly WatchedWindowService windows = new();
    private IReadOnlyList<WatchedWindowService.WindowInfo> availableWindows = [];
    private int step;
    public SetupWindow(CompanionConfiguration configuration) { InitializeComponent(); Icon = new BitmapImage(new Uri(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Yuki", "Idle", "idle_000.png"), UriKind.Absolute)); this.configuration = configuration; ShowStep(); }
    private void ShowStep()
    {
        StepTitle.Text = step switch { 0 => "Let’s set up your app companion.", 1 => "What should your companion be called?", 2 => "What window should she be able to look at?", 3 => "Connect Chrome or Edge", _ => "Your companion is ready!" };
        StepBody.Text = step switch { 0 => "Yuki stays on your desktop and talks through your normal logged-in ChatGPT conversation in Chrome or Edge. This short setup covers the pieces she needs.", 1 => "This name appears in the companion bubble and in your chat transcript. You can change it later in Settings.", 2 => "Choose the exact open window Yuki should be able to see. The list shows the program and window title together. Keep Minecraft open, then press Refresh and choose the game window rather than the launcher.", 3 => "Open Chrome or Edge’s extension page, load the matching extension folder included with this download, then open your Yuki — App Companion conversation and bind that tab from the Yuki extension menu.", _ => "Yuki is ready. Keep the selected window open, and keep the bound ChatGPT tab open in your browser." };
        NameBox.Visibility = step == 1 ? Visibility.Visible : Visibility.Collapsed;
        WindowBox.Visibility = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        RefreshWindowButton.Visibility = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        BrowserButtons.Visibility = step == 3 ? Visibility.Visible : Visibility.Collapsed;
        BackButton.Visibility = step > 0 && step < 4 ? Visibility.Visible : Visibility.Collapsed;
        NextButton.Content = step >= 4 ? "Finish" : "Continue";
        if (step == 1) { NameBox.Text = configuration.CompanionDisplayName; NameBox.Focus(); }
        if (step == 2) { RefreshApplications(); }
    }

    private void RefreshApplications()
    {
        availableWindows = windows.Discover();
        WindowBox.ItemsSource = availableWindows;
        var watched = configuration.WatchedApplication;
        WindowBox.SelectedItem = availableWindows.FirstOrDefault(item => string.Equals(item.Identifier, watched?.Identifier, StringComparison.OrdinalIgnoreCase) && string.Equals(item.Title, watched?.WindowIdentifier, StringComparison.OrdinalIgnoreCase)) ?? availableWindows.FirstOrDefault();
    }

    private void RefreshWindows(object sender, RoutedEventArgs e) => RefreshApplications();

    private void Back(object sender, RoutedEventArgs e) { if (step > 0) { step--; ShowStep(); } }

    private void Next(object sender, RoutedEventArgs e)
    {
        if (step == 1)
        {
            if (string.IsNullOrWhiteSpace(NameBox.Text)) { System.Windows.MessageBox.Show("Choose a name for Yuki first.", Title); return; }
            configuration.CompanionDisplayName = NameBox.Text.Trim();
        }
        if (step == 2)
        {
            if (WindowBox.SelectedItem is not WatchedWindowService.WindowInfo selected)
            { System.Windows.MessageBox.Show("Open the window you want Yuki to watch, then refresh this list and choose it.", Title); return; }
            configuration.WatchedApplication = new() { DisplayName = selected.ProcessName, Identifier = selected.Identifier, WindowIdentifier = selected.Title };
        }
        if (step >= 4) { configuration.OnboardingCompleted = true; configuration.Save(); DialogResult = true; Close(); return; }
        step++; ShowStep();
    }

    private void OpenChromeExtensions(object sender, RoutedEventArgs e)
    {
        OpenExtensionsPage("chrome://extensions", "Open Google Chrome and enter chrome://extensions in its address bar.");
    }

    private void OpenEdgeExtensions(object sender, RoutedEventArgs e)
    {
        OpenExtensionsPage("edge://extensions", "Open Microsoft Edge and enter edge://extensions in its address bar.");
    }

    private void OpenExtensionsPage(string address, string fallback)
    {
        try { Process.Start(new ProcessStartInfo { FileName = address, UseShellExecute = true }); }
        catch { System.Windows.MessageBox.Show(fallback, Title); }
    }
}
