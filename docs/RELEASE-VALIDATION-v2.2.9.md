# Codex Theme Switch 2.2.9 发布验证

验证对象包括当前源码、macOS 实机 Codex、最终交付 ZIP，以及 Windows 11 云端新用户安装模拟。

## macOS 实机

- 官方 Codex：`26.715.31925`，未修改 `.app`、`app.asar` 或代码签名。
- `skin-01..07` 浅色主题逐套切换，顶栏、输出弹层、正文和 composer 对比审计全部通过。
- 七套浅色主题的 composer 原生深色层数量均为 `0`；`skin-08` 保持深色渐变，不被浅色保护规则改亮。
- 八套主题发送按钮图标对比度依次为 `5.23 / 6.34 / 4.96 / 6.36 / 6.75 / 5.79 / 8.49 / 8.40`，全部高于图形控件 `3:1` 要求。
- Miku 最终截图视觉审查 `96/100`，黑色侧边、底带和低对比文字已消失。
- macOS 与 Windows Bash 静态测试均通过。

实机审计脚本：`macos/tests/contrast-audit-live.mjs`。

## macOS 发布 ZIP

最终包在全新临时 `HOME` 中执行 `macos/tests/release-install-smoke.sh`，验证：

- 衣橱 `.app` ad-hoc 签名与 Universal 2 的 `arm64`、`x86_64` 切片；
- 隔离安装、引擎 SHA-256 清单、桌面启动器、十个主题入口；
- 活动主题切换、配置恢复和卸载清理。

## Windows 11

GitHub Actions `windows-latest` 使用与交付包相同的目录结构模拟全新用户：

- 安装器、桌面和开始菜单快捷方式；
- WPF 衣橱编译并启动；
- 十个主题入口、二次原子安装、恢复原皮与卸载清理；
- PowerShell、JavaScript、窗口缩放几何和主题 payload 测试。

当前源码生成的 Windows ZIP 已在 GitHub Actions 通过完整新用户安装模拟：
https://github.com/myxsf/CodexThemeSwitch/actions/runs/29653100900

公开发布后的 Windows ZIP 已由 `workflow_dispatch` 从 GitHub Release 地址重新下载并通过同一套完整安装模拟：
https://github.com/myxsf/CodexThemeSwitch/actions/runs/29653206699

## 验证边界

GitHub Windows 运行器没有 Microsoft Store 官方 Codex，因此云端仅验证安装器、衣橱和主题资源，不伪造“已完成官方 Windows Codex 实际注入”。真实 Store 包发现、CDP 注入和窗口交互仍建议在装有官方 Codex 的 Windows 11 设备上人工复核。

macOS 应用当前为 ad-hoc 签名；公开分发可能出现 Gatekeeper 提示。Windows 包未使用商业 Authenticode 签名，可能触发 SmartScreen。
