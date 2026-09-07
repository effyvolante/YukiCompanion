using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;

namespace YukiCompanion.Windows;

public partial class SettingsWindow : Window
{
    private readonly CompanionConfiguration configuration;
    private readonly WatchedWindowService windows = new();
    private IReadOnlyList<WatchedWindowService.ApplicationInfo> applications = [];
    private IReadOnlyList<WatchedWindowService.WindowInfo> selectedWindows = [];
    public event Action? Saved;

    public SettingsWindow(CompanionConfiguration configuration)
    {
        InitializeComponent();
        this.configuration = configuration;
        NameBox.Text = configuration.CompanionDisplayName;
        ConversationBox.Text = configuration.ChromeConversation;
        AutomaticLookBox.IsChecked = configuration.AutomaticLook;
        LaunchAtLoginBox.IsChecked = configuration.LaunchAtLogin;
        AutomaticUpdatesBox.IsChecked = configuration.AutomaticUpdates;
        ThemeBox.ItemsSource = new[] { new ThemeChoice("Yuki", "Yuki") };
        ThemeBox.SelectedValue = configuration.ThemeId;
        RefreshApplicationList();
    }

    private void RefreshApplications(object sender, RoutedEventArgs e) => RefreshApplicationList();

    private void RefreshApplicationList()
    {
        applications = windows.DiscoverApplications();
        ApplicationBox.ItemsSource = applications;
        var watched = configuration.WatchedApplication;
        ApplicationBox.SelectedItem = applications.FirstOrDefault(item => string.Equals(item.Identifier, watched?.Identifier, StringComparison.OrdinalIgnoreCase))
            ?? applications.FirstOrDefault();
        if (ApplicationBox.SelectedItem is null) WindowBox.ItemsSource = null;
    }

    private void ApplicationChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ApplicationBox.SelectedItem is not WatchedWindowService.ApplicationInfo application) return;
        selectedWindows = application.Windows;
        WindowBox.ItemsSource = selectedWindows;
        var previousTitle = configuration.WatchedApplication?.WindowIdentifier;
        WindowBox.SelectedItem = selectedWindows.FirstOrDefault(item => string.Equals(item.Title, previousTitle, StringComparison.OrdinalIgnoreCase))
            ?? selectedWindows.FirstOrDefault();
    }

    private void WindowChanged(object sender, SelectionChangedEventArgs e) { }

    private void Save(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(NameBox.Text)) { System.Windows.MessageBox.Show("Choose a name for Yuki first.", Title); return; }
        configuration.CompanionDisplayName = NameBox.Text.Trim();
        configuration.ThemeId = (ThemeBox.SelectedValue as string) ?? "Yuki";
        configuration.ChromeConversation = ConversationBox.Text.Trim().Length == 0 ? "Yuki — App Companion" : ConversationBox.Text.Trim();
        configuration.AutomaticLook = AutomaticLookBox.IsChecked == true;
        configuration.LaunchAtLogin = LaunchAtLoginBox.IsChecked == true;
        configuration.AutomaticUpdates = AutomaticUpdatesBox.IsChecked != false;
        if (ApplicationBox.SelectedItem is WatchedWindowService.ApplicationInfo application)
        {
            var window = WindowBox.SelectedItem as WatchedWindowService.WindowInfo ?? application.Windows.FirstOrDefault();
            configuration.WatchedApplication = new WatchedApplication { DisplayName = application.DisplayName, Identifier = application.Identifier, WindowIdentifier = window?.Title };
        }
        configuration.Save();
        Saved?.Invoke();
        DialogResult = true;
        Close();
    }

    private void Cancel(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }

    private void OpenChromeExtensions(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo { FileName = "chrome://extensions", UseShellExecute = true }); }
        catch { System.Windows.MessageBox.Show("Open Google Chrome and enter chrome://extensions in its address bar.", Title); }
    }

    private sealed record ThemeChoice(string Id, string Name);
}
