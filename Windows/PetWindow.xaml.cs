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
    private int frame;
    private DateTime nextBlink = DateTime.UtcNow.AddSeconds(5);
    private double dragStartLeft;
    private double dragStartTop;

    public PetWindow(CompanionWindow chat)
    {
        InitializeComponent();
        this.chat = chat;
        chat.VisualStateChanged += SetState;
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
        state = requested switch { "answerComplete" => "answerComplete", "error" => "error", "thinking" => "thinking", "replying" => "replying", _ => "idle" };
        frame = 0;
        timer.Interval = TimeSpan.FromMilliseconds(state == "thinking" ? 280 : state == "replying" ? 240 : state == "answerComplete" ? 200 : 360);
        timer.Start();
        Advance();
    }

    private void Advance()
    {
        var animation = state switch
        {
            "thinking" => new Animation("Thinking", "thinking_", 10, true),
            "replying" => new Animation("Replying", "replying_", 7, true),
            "answerComplete" => new Animation("AnswerComplete", "answercomplete_", 6, false),
            "error" => new Animation("Error", "error_", 8, false),
            "blink" => new Animation("Blink", "blink_", 5, false),
            _ => new Animation("Idle", "idle_", 7, true)
        };
        var path = System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Yuki", animation.Folder, $"{animation.Prefix}{frame:000}.png");
        if (System.IO.File.Exists(path)) Sprite.Source = new BitmapImage(new Uri(path, UriKind.Absolute));
        frame++;
        if (frame >= animation.Count)
        {
            if (animation.Loop) frame = 0;
            else { state = "idle"; frame = 0; timer.Interval = TimeSpan.FromMilliseconds(360); }
        }
        if (state == "idle" && DateTime.UtcNow >= nextBlink) { state = "blink"; frame = 0; nextBlink = DateTime.UtcNow.AddSeconds(5); }
    }

    private readonly record struct Animation(string Folder, string Prefix, int Count, bool Loop);
}
