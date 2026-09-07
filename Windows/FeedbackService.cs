using System.Diagnostics;
using System.Windows;

namespace YukiCompanion.Windows;

public static class FeedbackService
{
    public const string FeedbackUrl = "https://github.com/effyvolante/YukiCompanion/issues/new?template=feedback.yml&title=Feedback%20from%20Yuki%20Companion";

    public static void Open(Window owner)
    {
        try { Process.Start(new ProcessStartInfo { FileName = FeedbackUrl, UseShellExecute = true }); }
        catch { System.Windows.MessageBox.Show(owner, "Open this address in your browser to send feedback:\n\n" + FeedbackUrl, "Yuki feedback", MessageBoxButton.OK, MessageBoxImage.Information); }
    }
}
