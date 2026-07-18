# Codex 主题衣橱（Windows）

Windows 版使用官方 Codex Desktop 的本机回环 CDP，不修改 `WindowsApps`、`app.asar` 或官方签名。

## 安装

在 Windows PowerShell 5.1 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\install-dream-skin.ps1
```

安装器会把完整引擎部署到 `%LOCALAPPDATA%\Programs\CodexThemeWardrobe`，编译并打开 **Codex Theme Wardrobe.exe**，同时创建桌面和开始菜单入口。WPF 软件使用 Windows 自带的 .NET Framework，不需要 NuGet。

## 使用

- 在衣橱中左右拖动、触摸滑动或使用鼠标滚轮浏览主题。
- 点击“应用此主题”后才会真正切换，快速浏览不会反复注入或闪烁。
- “Codex 原皮”会停止注入器并验证 CSS、DOM 和主题标记已经完整移除。
- 命令行也可以使用：

```powershell
.\windows\scripts\theme-windows.ps1 list
.\windows\scripts\theme-windows.ps1 switch skin-05 -RestartExisting
.\windows\scripts\theme-windows.ps1 switch qq2007
.\windows\scripts\theme-windows.ps1 switch original
.\windows\scripts\theme-windows.ps1 status -Deep
```

首次给已经打开的 Codex 加皮肤时需要重启一次，以便用 `127.0.0.1` 调试端口重新启动。之后均为热切换。

## 验证与恢复

```powershell
.\windows\tests\run-tests.ps1
.\windows\scripts\verify-dream-skin.ps1 -ExpectedTheme skin-05 -ScreenshotPath "$HOME\Desktop\codex-theme.png"
.\windows\scripts\restore-dream-skin.ps1 -RestartCodex
```

QQ 窗口提供四边四角共 8 个缩放热区，右上角按钮连接真实最小化、最大化/还原和关闭动作。最大化时热区会自动禁用，还原后恢复；最小尺寸为 760×560。

Windows 实机验收还应覆盖：八方向缩放、最大化精确还原、原皮往返、所有主题循环、唯一注入器、错误日志为空以及原生侧栏/输入框可用。静态套件已包含 10 组缩放几何断言，但不能替代 Windows 11 真机。

## 打包

```powershell
.\windows\scripts\build-release.ps1
```

输出位于 `windows\release\`，包含 ZIP 和 SHA-256。未使用商业代码签名证书的 EXE 可能触发 SmartScreen，这是签名信誉问题，不代表程序修改了 Codex。
