# Codex Theme Switch 2.2.8 发布验证

验证对象是 GitHub Release 中用户实际下载的 ZIP，不是只验证源码目录。

## macOS

在安装有官方签名 Codex 的 macOS 上创建临时、全新的 `HOME`，执行：

- 解压 `Codex-Theme-Wardrobe-v2.2.8-macos-universal.zip`；
- 严格验证衣橱 `.app` 签名；
- 验证 `arm64` 与 `x86_64` 两个切片；
- 模拟首次启动后已有 `~/.codex/config.toml` 的新用户；
- 安装到隔离的 `~/.codex/codex-dream-skin-studio`；
- 创建并验证六个桌面启动器；
- 验证完整引擎 SHA-256 清单；
- 验证 `skin-01..08` 与 `qq2007` 全部安装；
- 预切换黑金主题并验证活动主题与资源；
- 恢复原始 Codex 配置，确认字节一致。

结果：通过。测试脚本为 `macos/tests/release-install-smoke.sh`。

此外，当前维护机上的官方 Codex 已完成八主题实时 DOM、原生项目栏、输入框、Add 菜单、延迟切换和恢复验证。

## Windows 11

GitHub Actions `windows-latest` 从公开 Release URL 下载 Windows ZIP，并在隔离的
`LOCALAPPDATA`/`APPDATA`/`USERPROFILE` 中模拟新用户：

- 从 ZIP 运行原始安装器；
- 创建并验证桌面与开始菜单快捷方式；
- 解析系统 WPF 程序集并编译 `Codex Theme Wardrobe.exe`；
- 启动 WPF 衣橱，保持运行 3 秒；
- 验证 10 个目录项（原皮、八主题、QQ）；
- 执行 PowerShell、JavaScript、窗口缩放几何和主题 payload 测试；
- 第二次安装，验证原子替换不会保留陈旧文件；
- 恢复原皮、卸载并验证 `original/off` 状态、安装目录与快捷方式清理。

结果：通过。公开证据：
https://github.com/myxsf/CodexThemeSwitch/actions/runs/29649961129

测试脚本为 `windows/tests/release-install-smoke.ps1`。

## 验证边界

GitHub Windows 运行器没有 Microsoft Store 官方 Codex，因此使用临时假包提供
`AppxManifest.xml`、`ChatGPT.exe` 和 Node 运行时，仅验证安装器与衣橱，不伪造
“已完成官方 Windows Codex 实际注入”。

Windows 上最终的主题注入、Microsoft Store 包发现、真实 Codex CDP 和八方向窗口
缩放仍应在安装官方 Codex 的交互式 Windows 11 机器上做发布后人工验收。

macOS 原生侧栏鼠标拖到 240px/420px 的自动化服务在本轮不可用，也保留为人工验收项；
其 `ResizeObserver` 同步和稳定几何检查已通过。
