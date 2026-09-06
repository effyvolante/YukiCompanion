using System.Windows;

namespace YukiCompanion.Windows;

public partial class SetupWindow : Window
{
    private readonly CompanionConfiguration configuration;
    private readonly WatchedWindowService windows = new();
    private IReadOnlyList<WatchedWindowService.WindowInfo> choices = [];
    private int step;
    public SetupWindow(CompanionConfiguration configuration) { InitializeComponent(); this.configuration = configuration; ShowStep(); }
    private void ShowStep()
    {
        StepTitle.Text = step switch { 0 => "Let’s set up your companion.", 1 => "What should your companion be called?", 2 => "What app should your companion be able to look at?", 3 => "Connect Chrome", _ => "Your companion is ready!" };
        StepBody.Text = step switch { 0 => "Yuki will appear as a small desktop companion and use your normal ChatGPT conversation through Chrome.", 1 => "You can change this later in Settings.", 2 => "Choose a visible application window. Yuki will only capture this selected window when you ask her to look.", 3 => "Open ChatGPT in Chrome, load the Yuki Companion extension, and bind the conversation you want to use.", _ => "Click Done to launch your companion." };
        NameBox.Visibility = step == 1 ? Visibility.Visible : Visibility.Collapsed;
        WindowBox.Visibility = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        if (step == 1) { NameBox.Text = configuration.CompanionDisplayName; NameBox.Focus(); }
        if (step == 2) { choices = windows.Discover(); WindowBox.ItemsSource = choices; if (choices.Count > 0) WindowBox.SelectedIndex = 0; }
    }
    private void Next(object sender, RoutedEventArgs e)
    {
        if (step == 1 && !string.IsNullOrWhiteSpace(NameBox.Text)) configuration.CompanionDisplayName = NameBox.Text.Trim();
        if (step == 2 && WindowBox.SelectedItem is WatchedWindowService.WindowInfo selected) configuration.WatchedApplication = new() { DisplayName = selected.Title, Identifier = selected.Identifier, WindowIdentifier = selected.Title };
        if (step >= 4) { configuration.OnboardingCompleted = true; configuration.Save(); DialogResult = true; Close(); return; }
        step++; ShowStep();
    }
}
