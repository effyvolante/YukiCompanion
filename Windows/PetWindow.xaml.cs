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
        chat.StateChanged += SetState;
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
            "thinking" => (folder: "Thinking", prefix: "thinking_", count: 10, loop: true),
            "replying" => ("Replying", "replying_", 7, true),
            "answerComplete" => ("AnswerComplete", "answercomplete_", 6, false),
            "error" => ("Error", "error_", 8, false),
            "blink" => ("Blink", "blink_", 5, false),
            _ => ("Idle", "idle_", 7, true)
        };
        var path = System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Yuki", animation.folder, $"{animation.prefix}{frame:000}.png");
        if (File.Exists(path)) Sprite.Source = new BitmapImage(new Uri(path, UriKind.Absolute));
        frame++;
        if (frame >= animation.count)
        {
            if (animation.loop) frame = 0;
            else { state = "idle"; frame = 0; timer.Interval = TimeSpan.FromMilliseconds(360); }
        }
        if (state == "idle" && DateTime.UtcNow >= nextBlink) { state = "blink"; frame = 0; nextBlink = DateTime.UtcNow.AddSeconds(5); }
    }
}
