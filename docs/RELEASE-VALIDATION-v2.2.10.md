# Codex Theme Switch 2.2.10 发布验证

2.2.10 是 Windows 运行时兼容补丁，并包含 2.2.9 的全部浅色主题与 composer 对比度修复。

## 客户报错根因

部分 Windows Store Codex 安装中，包目录下的 `node.exe` 可以被脚本发现，但 Windows 应用包策略拒绝从该位置直接执行。旧代码在执行 `node.exe --version` 时因 `ErrorActionPreference=Stop` 直接退出，无法尝试其他候选或回退路径。

## 修复

- 每个 Node 候选都独立捕获执行错误，不会因首个“拒绝访问”终止安装。
- 官方 Codex 包内 Node 无法原位执行时，复制到 `%LOCALAPPDATA%\CodexDreamSkinStudio\runtime\node.exe`。
- 对本地副本执行 `Unblock-File`，并要求版本为 Node.js 20+ 后才保存到运行状态。
- 如果复制和 PATH 均不可用，返回包含检查路径的明确错误，而不是原始 PowerShell `NativeCommandFailed`。

## 自动验证

- Windows 发布烟测强制把包内 Node 标记为不可执行，验证安装器创建本地副本并能正常运行 `--version`。
- 随后继续执行 WPF 衣橱编译/启动、十个主题入口、二次原子安装、恢复原皮与卸载清理。
- macOS 与 Windows 静态测试继续通过。
- 当前源码生成的 Windows ZIP 已强制模拟包内 Node 拒绝访问，并通过本地副本、WPF 编译/启动、重装、恢复和卸载测试：
  <https://github.com/myxsf/CodexThemeSwitch/actions/runs/29669812169>
- 公开 Release Windows ZIP 已从 GitHub 下载，并再次通过同一套包内 Node 拒绝访问回退和完整安装测试：
  <https://github.com/myxsf/CodexThemeSwitch/actions/runs/29669902996>

## 验证边界

云端测试覆盖与客户报错相同的控制流，但不能模拟客户电脑的全部终端安全软件、AppLocker 或 WDAC 策略。如果本地副本也被企业策略禁止执行，需要由管理员允许 `%LOCALAPPDATA%\CodexDreamSkinStudio\runtime\node.exe`，或在 PATH 安装 Node.js 20+。
