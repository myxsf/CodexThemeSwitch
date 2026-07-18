using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace CodexThemeWardrobe {
  internal sealed class ThemeItem {
    public string Id, Name, Subtitle, Tagline, Preview, Profile;
    public string Background, Panel, PanelAlt, Accent, AccentAlt, TextColor;
    public bool Active, Experimental;
  }

  internal sealed class WardrobeWindow : Window {
    private readonly StackPanel cards = new StackPanel();
    private readonly ScrollViewer scroller = new ScrollViewer();
    private readonly TextBlock status = new TextBlock();
    private readonly Button applySelected = new Button();
    private readonly List<ThemeItem> themes = new List<ThemeItem>();
    private string scriptPath;
    private int selectedIndex;
    private bool dragging;
    private Point dragStart;
    private double dragOffset;
    private DispatcherTimer animation;

    public WardrobeWindow() {
      Title = "Codex 主题衣橱";
      Width = 1000; Height = 650; MinWidth = 720; MinHeight = 500;
      WindowStartupLocation = WindowStartupLocation.CenterScreen;
      Background = new SolidColorBrush(Color.FromRgb(241, 247, 252));
      FontFamily = new FontFamily("Microsoft YaHei UI");
      scriptPath = FindThemeScript();
      Content = BuildLayout();
      Loaded += delegate { LoadThemes(); };
    }

    private UIElement BuildLayout() {
      Grid root = new Grid();
      root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
      root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
      root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

      Border header = new Border { Background = Brushes.White, Padding = new Thickness(26, 22, 26, 18), BorderBrush = new SolidColorBrush(Color.FromRgb(212, 226, 237)), BorderThickness = new Thickness(0, 0, 0, 1) };
      Grid headerGrid = new Grid();
      headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
      headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
      StackPanel title = new StackPanel();
      title.Children.Add(new TextBlock { Text = "Codex 主题衣橱", FontSize = 28, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(22, 53, 80)) });
      title.Children.Add(new TextBlock { Text = "左右拖动、触摸滑动或滚轮浏览；只在点击应用时更换主题", Margin = new Thickness(0, 5, 0, 0), Foreground = new SolidColorBrush(Color.FromRgb(91, 116, 136)) });
      title.Children.Add(new TextBlock { Text = "作者 myxsf · 禁止开源转卖与盗版", Margin = new Thickness(0, 6, 0, 0), FontSize = 11, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(194, 92, 31)) });
      headerGrid.Children.Add(title);
      Button refresh = MakeButton("重新检测", false);
      refresh.Click += delegate { LoadThemes(); };
      Grid.SetColumn(refresh, 1); headerGrid.Children.Add(refresh);
      header.Child = headerGrid; root.Children.Add(header);

      scroller.HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden;
      scroller.VerticalScrollBarVisibility = ScrollBarVisibility.Disabled;
      scroller.PanningMode = PanningMode.HorizontalOnly;
      scroller.CanContentScroll = false;
      scroller.Padding = new Thickness(34, 32, 34, 30);
      cards.Orientation = Orientation.Horizontal;
      scroller.Content = cards;
      scroller.PreviewMouseWheel += OnWheel;
      scroller.PreviewMouseLeftButtonDown += OnDragStart;
      scroller.PreviewMouseMove += OnDragMove;
      scroller.PreviewMouseLeftButtonUp += OnDragEnd;
      scroller.LostMouseCapture += delegate { dragging = false; };
      scroller.ScrollChanged += OnScrollChanged;
      Grid.SetRow(scroller, 1); root.Children.Add(scroller);

      Border footer = new Border { Background = Brushes.White, Padding = new Thickness(24, 14, 24, 14), BorderBrush = new SolidColorBrush(Color.FromRgb(212, 226, 237)), BorderThickness = new Thickness(0, 1, 0, 0) };
      Grid footerGrid = new Grid();
      footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
      footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
      status.Text = "正在读取主题目录…"; status.VerticalAlignment = VerticalAlignment.Center; status.Foreground = new SolidColorBrush(Color.FromRgb(76, 102, 123));
      footerGrid.Children.Add(status);
      applySelected.Content = "应用当前主题"; applySelected.Padding = new Thickness(18, 9, 18, 9); applySelected.IsEnabled = false;
      applySelected.Click += delegate { if (themes.Count > 0) ApplyTheme(themes[selectedIndex]); };
      Grid.SetColumn(applySelected, 1); footerGrid.Children.Add(applySelected);
      footer.Child = footerGrid; Grid.SetRow(footer, 2); root.Children.Add(footer);
      return root;
    }

    private Button MakeButton(string text, bool primary) {
      Button button = new Button { Content = text, Padding = new Thickness(14, 8, 14, 8), Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
      if (primary) { button.Background = new SolidColorBrush(Color.FromRgb(26, 116, 201)); button.Foreground = Brushes.White; }
      return button;
    }

    private string FindThemeScript() {
      string baseDir = AppDomain.CurrentDomain.BaseDirectory;
      string[] candidates = {
        Path.Combine(baseDir, "windows", "scripts", "theme-windows.ps1"),
        Path.Combine(baseDir, "scripts", "theme-windows.ps1"),
        Path.GetFullPath(Path.Combine(baseDir, "..", "scripts", "theme-windows.ps1")),
        Path.GetFullPath(Path.Combine(baseDir, "..", "..", "scripts", "theme-windows.ps1"))
      };
      foreach (string candidate in candidates) if (File.Exists(candidate)) return candidate;
      return candidates[0];
    }

    private string RunScript(string arguments) {
      if (!File.Exists(scriptPath)) throw new FileNotFoundException("主题引擎未安装", scriptPath);
      ProcessStartInfo info = new ProcessStartInfo();
      info.FileName = "powershell.exe";
      info.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" " + arguments;
      info.UseShellExecute = false; info.CreateNoWindow = true; info.RedirectStandardOutput = true; info.RedirectStandardError = true;
      info.StandardOutputEncoding = Encoding.UTF8; info.StandardErrorEncoding = Encoding.UTF8;
      using (Process process = Process.Start(info)) {
        string output = process.StandardOutput.ReadToEnd();
        string error = process.StandardError.ReadToEnd();
        process.WaitForExit();
        if (process.ExitCode != 0) throw new InvalidOperationException(String.IsNullOrWhiteSpace(error) ? output : error);
        return output.Trim();
      }
    }

    private static string Value(IDictionary dict, string key) {
      return dict.Contains(key) && dict[key] != null ? Convert.ToString(dict[key]) : "";
    }

    private void LoadThemes() {
      status.Text = "正在读取主题目录…"; applySelected.IsEnabled = false;
      ThreadPool.QueueUserWorkItem(delegate {
        try {
          string json = RunScript("list -Json");
          object parsed = new JavaScriptSerializer().DeserializeObject(json);
          ArrayList values = new ArrayList();
          object[] array = parsed as object[];
          if (array != null) values.AddRange(array); else values.Add(parsed);
          List<ThemeItem> loaded = new List<ThemeItem>();
          foreach (object item in values) {
            IDictionary dict = item as IDictionary; if (dict == null) continue;
            IDictionary colors = dict.Contains("colors") ? dict["colors"] as IDictionary : null;
            loaded.Add(new ThemeItem { Id = Value(dict, "id"), Name = Value(dict, "name"), Subtitle = Value(dict, "subtitle"),
              Tagline = Value(dict, "tagline"), Preview = Value(dict, "preview"), Profile = Value(dict, "profile"),
              Background = colors == null ? "" : Value(colors, "background"), Panel = colors == null ? "" : Value(colors, "panel"),
              PanelAlt = colors == null ? "" : Value(colors, "panelAlt"), Accent = colors == null ? "" : Value(colors, "accent"),
              AccentAlt = colors == null ? "" : Value(colors, "accentAlt"), TextColor = colors == null ? "" : Value(colors, "text"),
              Active = dict.Contains("active") && Convert.ToBoolean(dict["active"]),
              Experimental = dict.Contains("experimental") && Convert.ToBoolean(dict["experimental"]) });
          }
          Dispatcher.Invoke(delegate { RenderThemes(loaded); });
        } catch (Exception error) { Dispatcher.Invoke(delegate { status.Text = "读取失败：" + error.Message; }); }
      });
    }

    private void RenderThemes(List<ThemeItem> loaded) {
      themes.Clear(); themes.AddRange(loaded); cards.Children.Clear(); selectedIndex = 0;
      for (int i = 0; i < themes.Count; i++) {
        ThemeItem theme = themes[i];
        if (theme.Active) selectedIndex = i;
        cards.Children.Add(BuildCard(theme));
      }
      status.Text = themes.Count == 0 ? "没有可用主题" : String.Format("已载入 {0} 套主题 · 可拖动、触摸滑动或滚轮浏览", themes.Count);
      applySelected.IsEnabled = themes.Count > 0;
      Dispatcher.BeginInvoke(new Action(delegate { SmoothScroll(selectedIndex * 324.0); }), DispatcherPriority.Loaded);
    }

    private UIElement BuildCard(ThemeItem theme) {
      Border card = new Border { Width = 300, Margin = new Thickness(0, 0, 24, 0), Background = Brushes.White,
        CornerRadius = new CornerRadius(18), BorderThickness = new Thickness(theme.Active ? 3 : 1),
        BorderBrush = new SolidColorBrush(theme.Active ? Color.FromRgb(23, 142, 121) : Color.FromRgb(215, 226, 235)),
        Padding = new Thickness(0), Cursor = Cursors.Hand };
      Grid grid = new Grid();
      grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(190) });
      grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
      Border preview = new Border { Background = new SolidColorBrush(Color.FromRgb(224, 235, 244)), CornerRadius = new CornerRadius(15, 15, 0, 0), ClipToBounds = true };
      Grid previewContent = new Grid();
      if (!String.IsNullOrWhiteSpace(theme.Preview) && File.Exists(theme.Preview)) {
        try { preview.Background = new ImageBrush(new BitmapImage(new Uri(theme.Preview))) { Stretch = Stretch.UniformToFill }; } catch { }
      } else if (theme.Id == "original") {
        previewContent.Children.Add(new TextBlock { Text = "Codex", FontSize = 42, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(34, 45, 57)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
      } else {
        preview.Background = new LinearGradientBrush(ParseColor(theme.Background, Color.FromRgb(236, 245, 250)), ParseColor(theme.PanelAlt, Color.FromRgb(220, 235, 245)), 35);
      }
      if (theme.Id != "original" && theme.Profile != "qq2007") previewContent.Children.Add(BuildThemeShell(theme));
      Border watermark = new Border { Background = new SolidColorBrush(Color.FromArgb(150, 7, 12, 20)), CornerRadius = new CornerRadius(10), Padding = new Thickness(8, 4, 8, 4), Margin = new Thickness(10), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Bottom };
      watermark.Child = new TextBlock { Text = "© myxsf · 禁止转卖 / 盗版", Foreground = Brushes.White, FontSize = 10, FontWeight = FontWeights.Bold };
      previewContent.Children.Add(watermark); preview.Child = previewContent;
      grid.Children.Add(preview);
      StackPanel copy = new StackPanel { Margin = new Thickness(18, 16, 18, 18) };
      copy.Children.Add(new TextBlock { Text = theme.Name + (theme.Experimental ? "  实验" : ""), FontSize = 20, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(28, 55, 78)) });
      copy.Children.Add(new TextBlock { Text = String.IsNullOrWhiteSpace(theme.Subtitle) ? theme.Tagline : theme.Subtitle, Margin = new Thickness(0, 8, 0, 14), TextWrapping = TextWrapping.Wrap, Height = 44, Foreground = new SolidColorBrush(Color.FromRgb(91, 112, 130)) });
      Button apply = MakeButton(theme.Active ? "正在使用" : "应用此主题", true); apply.IsEnabled = !theme.Active;
      apply.Tag = theme; apply.Click += delegate(object sender, RoutedEventArgs e) { ApplyTheme((ThemeItem)((Button)sender).Tag); e.Handled = true; };
      copy.Children.Add(apply); Grid.SetRow(copy, 1); grid.Children.Add(copy); card.Child = grid;
      card.MouseLeftButtonUp += delegate { selectedIndex = themes.IndexOf(theme); SmoothScroll(selectedIndex * 324.0); };
      card.MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e) { if (e.ClickCount == 2) ApplyTheme(theme); };
      return card;
    }

    private static Color ParseColor(string value, Color fallback) {
      if (String.IsNullOrWhiteSpace(value)) return fallback;
      string clean = value.Trim().TrimStart('#');
      if (clean.Length != 6) return fallback;
      try { return Color.FromRgb(Convert.ToByte(clean.Substring(0, 2), 16), Convert.ToByte(clean.Substring(2, 2), 16), Convert.ToByte(clean.Substring(4, 2), 16)); }
      catch { return fallback; }
    }

    private static UIElement BuildThemeShell(ThemeItem theme) {
      Color panelColor = ParseColor(theme.Panel, Colors.White);
      Color panelAltColor = ParseColor(theme.PanelAlt, Color.FromRgb(235, 243, 249));
      Color accentColor = ParseColor(theme.Accent, Color.FromRgb(35, 139, 193));
      Color textColor = ParseColor(theme.TextColor, Color.FromRgb(28, 55, 78));
      Grid shell = new Grid { Margin = new Thickness(12) };
      shell.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(72) });
      shell.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
      Border side = new Border { Background = new SolidColorBrush(Color.FromArgb(226, panelColor.R, panelColor.G, panelColor.B)), CornerRadius = new CornerRadius(8), Padding = new Thickness(9) };
      StackPanel sideLines = new StackPanel();
      sideLines.Children.Add(new Border { Height = 7, Width = 30, HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new CornerRadius(3), Background = new SolidColorBrush(accentColor), Margin = new Thickness(0, 0, 0, 10) });
      for (int i = 0; i < 5; i++) sideLines.Children.Add(new Border { Height = i == 1 ? 15 : 6, CornerRadius = new CornerRadius(3), Background = new SolidColorBrush(Color.FromArgb(i == 1 ? (byte)52 : (byte)28, accentColor.R, accentColor.G, accentColor.B)), Margin = new Thickness(0, 0, 0, 7) });
      side.Child = sideLines; shell.Children.Add(side);
      StackPanel main = new StackPanel { Margin = new Thickness(9, 0, 0, 0) };
      Border hero = new Border { Height = 88, CornerRadius = new CornerRadius(9), Background = new SolidColorBrush(Color.FromArgb(220, panelAltColor.R, panelAltColor.G, panelAltColor.B)), BorderBrush = new SolidColorBrush(Color.FromArgb(90, accentColor.R, accentColor.G, accentColor.B)), BorderThickness = new Thickness(1), Padding = new Thickness(12) };
      StackPanel heroLines = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
      heroLines.Children.Add(new Border { Width = 80, Height = 8, HorizontalAlignment = HorizontalAlignment.Left, Background = new SolidColorBrush(Color.FromArgb(210, textColor.R, textColor.G, textColor.B)), CornerRadius = new CornerRadius(3), Margin = new Thickness(0, 0, 0, 7) });
      heroLines.Children.Add(new Border { Width = 112, Height = 5, HorizontalAlignment = HorizontalAlignment.Left, Background = new SolidColorBrush(Color.FromArgb(100, textColor.R, textColor.G, textColor.B)), CornerRadius = new CornerRadius(3), Margin = new Thickness(0, 0, 0, 9) });
      heroLines.Children.Add(new Border { Width = 54, Height = 15, HorizontalAlignment = HorizontalAlignment.Left, Background = new SolidColorBrush(accentColor), CornerRadius = new CornerRadius(5) });
      hero.Child = heroLines; main.Children.Add(hero);
      Border composer = new Border { Height = 28, Margin = new Thickness(0, 9, 0, 0), CornerRadius = new CornerRadius(8), Background = new SolidColorBrush(Color.FromArgb(232, panelColor.R, panelColor.G, panelColor.B)), BorderBrush = new SolidColorBrush(Color.FromArgb(160, accentColor.R, accentColor.G, accentColor.B)), BorderThickness = new Thickness(1) };
      main.Children.Add(composer); Grid.SetColumn(main, 1); shell.Children.Add(main);
      return shell;
    }

    private void ApplyTheme(ThemeItem theme) {
      applySelected.IsEnabled = false; status.Text = "正在切换到“" + theme.Name + "”…";
      ThreadPool.QueueUserWorkItem(delegate {
        try {
          RunScript("switch \"" + theme.Id.Replace("\"", "") + "\" -RestartExisting");
          Dispatcher.Invoke(delegate { status.Text = "已应用“" + theme.Name + "”"; LoadThemes(); });
        } catch (Exception error) { Dispatcher.Invoke(delegate { status.Text = "切换失败：" + error.Message; applySelected.IsEnabled = true; }); }
      });
    }

    private void OnWheel(object sender, MouseWheelEventArgs e) { SmoothScroll(scroller.HorizontalOffset - e.Delta * 0.9); e.Handled = true; }
    private void OnDragStart(object sender, MouseButtonEventArgs e) {
      if (FindParent<Button>(e.OriginalSource as DependencyObject) != null) return;
      dragging = true; dragStart = e.GetPosition(scroller); dragOffset = scroller.HorizontalOffset; scroller.CaptureMouse(); e.Handled = true;
    }
    private void OnDragMove(object sender, MouseEventArgs e) {
      if (!dragging || e.LeftButton != MouseButtonState.Pressed) return;
      double delta = e.GetPosition(scroller).X - dragStart.X; scroller.ScrollToHorizontalOffset(dragOffset - delta); e.Handled = true;
    }
    private void OnDragEnd(object sender, MouseButtonEventArgs e) { if (!dragging) return; dragging = false; scroller.ReleaseMouseCapture(); Snap(); e.Handled = true; }
    private void OnScrollChanged(object sender, ScrollChangedEventArgs e) {
      if (themes.Count > 0) selectedIndex = Math.Max(0, Math.Min(themes.Count - 1, (int)Math.Round(scroller.HorizontalOffset / 324.0)));
    }
    private void Snap() { SmoothScroll(selectedIndex * 324.0); }
    private void SmoothScroll(double destination) {
      if (animation != null) animation.Stop();
      double start = scroller.HorizontalOffset;
      double end = Math.Max(0, Math.Min(destination, scroller.ScrollableWidth));
      DateTime began = DateTime.UtcNow;
      animation = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
      animation.Tick += delegate {
        double t = (DateTime.UtcNow - began).TotalMilliseconds / 240.0;
        if (t >= 1) { scroller.ScrollToHorizontalOffset(end); animation.Stop(); return; }
        double eased = 1 - Math.Pow(1 - t, 3); scroller.ScrollToHorizontalOffset(start + (end - start) * eased);
      };
      animation.Start();
    }
    private static T FindParent<T>(DependencyObject node) where T : DependencyObject {
      while (node != null) { T match = node as T; if (match != null) return match; node = VisualTreeHelper.GetParent(node); }
      return null;
    }
  }

  public static class Program {
    [STAThread]
    public static void Main() {
      Application app = new Application();
      app.ShutdownMode = ShutdownMode.OnMainWindowClose;
      app.Run(new WardrobeWindow());
    }
  }
}
