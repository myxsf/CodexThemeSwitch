# Codex 万能皮肤衣橱

## 当前版本

- macOS 衣橱与引擎：`2.2.8`
- Windows 衣橱与引擎：`2.2.8`
- 主题目录协议：`themes/catalog.json` schema `1`

本项目通过本机回环 CDP 给官方 Codex Desktop 添加外部皮肤，不修改官方应用、`app.asar` 或代码签名。

## 内置主题

衣橱当前读取 10 个目录条目：

1. Codex 原皮
2. 粉系定制
3. 财神打工版
4. 红白科幻
5. 清透定制
6. 灵感小宇宙
7. 紫夜限定
8. 初音未来方向
9. 舞台黑金
10. 复古 QQ 2007

衣橱不再展示与实际注入不同的图库合成图。预览与运行时共用同一份纯背景、配色和布局语言；没有纯背景的主题直接用同源配色生成预览，不会把假的侧栏、输入框或按钮覆盖到 Codex 上。

## macOS

双击桌面的 `Codex 主题衣橱.app`。

- 触控板左右滑动、鼠标拖拽或左右箭头可浏览主题。
- 滑动吸附到下一张卡片后会延迟约 0.3 秒切换，连续操作会自动取消前一次待处理切换。
- 顶部“恢复原皮”会停止 watcher，并清除实时 CSS、主题属性、结构节点和附加卡片。
- “打开 Codex”会根据当前主题决定使用主题启动器还是官方原皮启动方式。
- 应用内置完整引擎；检测到本机版本较旧时会显示“安装/更新引擎”。

命令行入口：

```bash
~/.codex/codex-dream-skin-studio/scripts/theme-macos.sh list
~/.codex/codex-dream-skin-studio/scripts/theme-macos.sh skin-05
~/.codex/codex-dream-skin-studio/scripts/theme-macos.sh qq2007
~/.codex/codex-dream-skin-studio/scripts/theme-macos.sh original
```

QQ 主题使用 1440×1080 基准画布，按窗口宽高等比例缩放并水平居中。最大化时允许出现对称留边，以避免原型被横向拉伸。QQ 右上三键仅作原型装饰；窗口操作使用 Codex 原生 macOS 红黄绿控件，避免 Electron CDP 失效或要求额外辅助功能权限。

## Windows

在 Windows PowerShell 5.1 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\install-dream-skin.ps1
```

安装位置为 `%LOCALAPPDATA%\Programs\CodexThemeWardrobe`。WPF 软件使用系统 .NET Framework，不依赖 NuGet，支持触摸、鼠标拖拽、滚轮和吸附动画。

Windows QQ 窗口包含真实最小化、最大化/还原、关闭桥接，以及 `n/s/e/w/ne/nw/se/sw` 八方向缩放热区。最大化时缩放热区自动禁用，还原后恢复；西/北方向缩放会固定相反边，最小尺寸为 760×560。

Windows 源码、主题载荷与缩放几何自测已完成；正式发布前仍需在装有 Microsoft Store Codex 的 Windows 11 上运行：

```powershell
.\windows\tests\run-tests.ps1
.\windows\scripts\build-release.ps1
```

并完成真实 Codex 的所有主题循环、最大化/还原、边缘缩放、原皮清理和错误日志检查。

## 主题包扩展协议

`themes/catalog.json` 是跨平台只读目录。主题条目可以声明：

- `id`、`name`、`order`、`aliases`
- `profile` 与 `kind`
- `preview`：仅供衣橱展示
- `pack`、`image`：实际主题包及纯背景
- `colors`：受校验的颜色变量
- `platforms`、`enabled`、`experimental`
- `rights`、`publisher`、`packageVersion`、`minEngineVersion`、`sha256`

未来发布者上传主题时，客户端只应接受白名单 profile、图片和 JSON 元数据。远程主题包不得携带任意 JavaScript、PowerShell、Shell 或 CSS；下载后先校验 SHA-256、版本、平台、文件大小和目录穿越，再原子发布到主题库。

## 权利与发布说明

QQ、人物、明星或角色方向的预览/素材需要单独确认再分发权利。公开商业包不得把 `rights: review-required` 当成已获授权。面向客户发布前还需要：

- macOS Developer ID 签名、公证与 stapling
- Windows Authenticode 签名
- Windows 11 + Store Codex 真机验收
- 从最新 GitHub `main` 移植并通过 CI

## 已验证结果

- macOS 10 个目录条目加载成功。
- 原皮 → 8 套图库主题 → QQ 已逐套切换。
- 原皮停止 watcher；QQ 状态保持唯一 watcher。
- QQ 在 1362×945 与 1510×1084 视口保持 4:3，无横向溢出，响应式检查通过。
- 新版首页四个真实快捷按钮保持两列并完整位于真实输入框上方；原皮 → 紫夜 → QQ 往返通过，唯一 watcher 数量为 1。
- macOS Universal 2 应用包含 `arm64` 与 `x86_64`。
- Windows 跨平台静态测试通过；Windows WPF/Store Codex 真机项待 Windows 11 验证。
- 2.2.8 已逐套复核八套图库主题：恢复原生项目栏，消除项目栏/输入框重叠，把底部留白限制在窗口高度 12% 内，并排除复合海报中的烘焙假卡片。
- 侧栏镜像同步通过静态与稳定几何检查；受当前 macOS 自动化服务限制，240 → 420 → 原宽的原生鼠标拖动保留为人工验收项。
- QQ 2007 首次进入和页面重新加载会恢复参考侧栏比例；初始化完成后继续使用 Codex 原生拖动条，并让中间工作区实时跟随侧栏宽度。
- QQ 2007 仅在用户实际操作原生分隔器时记忆新宽度；任务切页、窗口缩放和 Codex 内部状态回写不会再导致侧栏穿透或线程内容横移。
