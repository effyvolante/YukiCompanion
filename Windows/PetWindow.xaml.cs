using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace YukiCompanion.Windows;

public partial class PetWindow : Window
{
    private readonly CompanionWindow chat;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(360) };
    private string state = "idle";
    private string theme = "Yuki";
    private int frame;
    private DateTime nextBlink = DateTime.UtcNow.AddSeconds(5);
    private double dragStartLeft;
    private double dragStartTop;

    public PetWindow(CompanionWindow chat)
    {
        InitializeComponent();
        Icon = new BitmapImage(new Uri(System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Yuki", "Idle", "idle_000.png"), UriKind.Absolute));
        this.chat = chat;
        chat.VisualStateChanged += SetState;
        chat.ThemeChanged += SetTheme;
        theme = chat.ThemeId;
        timer.Tick += (_, _) => Advance();
        SetState("idle");
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Right - Width - 28;
        Top = workArea.Bottom - Height - 28;
    }

    private void DragOrOpen(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;
        dragStartLeft = Left; dragStartTop = Top;
        try { DragMove(); } catch (InvalidOperationException) { }
        if (Math.Abs(Left - dragStartLeft) < 3 && Math.Abs(Top - dragStartTop) < 3) chat.ShowChat();
    }

    private void SetState(string requested)
    {
        state = requested switch { "answerComplete" => "answerComplete", "error" => "error", "thinking" => "thinking", "replying" => "replying", "look" => "look", _ => "idle" };
        frame = 0;
        timer.Interval = TimeSpan.FromMilliseconds(state == "thinking" ? 280 : state == "replying" ? 240 : state == "answerComplete" ? 200 : 360);
        timer.Start();
        Advance();
    }

    private void Advance()
    {
        var animation = state switch
        {
            "thinking" => new Animation("Thinking", "thinking_", 8, true),
            "replying" => new Animation("Replying", "replying_", 8, true),
            "answerComplete" => new Animation("AnswerComplete", "answercomplete_", 8, false),
            "error" => new Animation("Error", "error_", 8, false),
            "look" => new Animation("Look", "look_", 8, false),
            "blink" => new Animation("Idle", "idle_", 5, false),
            _ => new Animation("Idle", "idle_", 8, true)
        };
        var path = System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Themes", theme, animation.Folder, $"{theme.ToLowerInvariant()}_{animation.Prefix}{frame:000}.png");
        if (System.IO.File.Exists(path)) Sprite.Source = new BitmapImage(new Uri(path, UriKind.Absolute));
        frame++;
        if (frame >= animation.Count)
        {
            if (animation.Loop) frame = 0;
            else { state = "idle"; frame = 0; timer.Interval = TimeSpan.FromMilliseconds(360); }
        }
        if (state == "idle" && DateTime.UtcNow >= nextBlink) { state = "blink"; frame = 0; nextBlink = DateTime.UtcNow.AddSeconds(5); }
    }

    private void SetTheme(string selected) { theme = selected; state = "idle"; frame = 0; SetState("idle"); }

    private readonly record struct Animation(string Folder, string Prefix, int Count, bool Loop);
}
