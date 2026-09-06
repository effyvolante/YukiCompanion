using System.Windows;
using System.Windows.Input;

namespace YukiCompanion.Windows;

public partial class CompanionWindow : Window
{
    private readonly CompanionConfiguration configuration;
    public CompanionWindow(CompanionConfiguration configuration)
    {
        InitializeComponent();
        this.configuration = configuration;
        Width = Height = configuration.Size + 40;
        Title = configuration.CompanionDisplayName;
        CompanionName.Text = configuration.CompanionDisplayName;
    }

    private void Drag(object sender, MouseButtonEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) DragMove(); }
    private void OpenSettings(object sender, RoutedEventArgs e) => MessageBox.Show("Settings and setup will use your saved companion configuration.", configuration.CompanionDisplayName);
}
