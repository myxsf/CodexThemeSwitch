# Codex Theme Switch · Codex 主题衣橱

<p align="center">
  <strong>中文</strong> · <a href="./README.en.md">English</a>
</p>

<p align="center">
  <strong>给 Codex 桌面端换一张会呼吸的脸。</strong><br>
  外部主题 / 换肤工具 · 本机 CDP 注入 · 不改官方安装包
</p>

<p align="center">
  一张图，一种心情 · 写代码，也要有氛围感
</p>

<p align="center">
  非 OpenAI 官方产品。不修改 <code>.app</code> / <code>app.asar</code> / WindowsApps。
</p>

<p align="center">
  <a href="https://github.com/myxsf/CodexThemeSwitch/actions/workflows/ci.yml"><img src="https://github.com/myxsf/CodexThemeSwitch/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/myxsf/CodexThemeSwitch/releases/tag/v2.2.8"><img src="https://img.shields.io/github/v/release/myxsf/CodexThemeSwitch" alt="Release"></a>
</p>

## 项目归属与赞助

<p align="center">
  <strong>Codex Theme Switch · Codex 主题衣橱</strong><br>
  <sub>由 <a href="https://github.com/myxsf">myxsf</a> 维护 · 目前暂无赞助商</sub>
</p>

本项目未接受任何组织或服务商赞助，也不为第三方 API、中转站或商业服务背书。未来如有正式赞助，会在这里公开标注；未标注的第三方均与本项目无关。

## 效果预览

下面是 `2.2.8` 的脱敏实机截图，仅保留 Hero 与原生建议卡区域：

<p align="center">
  <img src="docs/images/theme-gallery-safe.png" alt="Codex Theme Wardrobe 2.2.8 实机主题联系表" width="1100">
</p>

一张图，一种心情。下面是对应的原型参考：

<p align="center">
  <img src="docs/images/gallery/skin-01.jpg" alt="粉系定制" width="900"><br>
  <sub>粉系定制</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-02.jpg" alt="财神打工" width="900"><br>
  <sub>财神打工版</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-03.jpg" alt="红白科幻" width="900"><br>
  <sub>红白科幻</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-04.jpg" alt="清透定制" width="900"><br>
  <sub>清透定制</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-05.jpg" alt="灵感小宇宙" width="900"><br>
  <sub>灵感小宇宙</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-06.jpg" alt="紫夜限定" width="900"><br>
  <sub>紫夜限定</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-07.jpg" alt="初音未来" width="900"><br>
  <sub>初音未来</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-08.jpg" alt="舞台黑金" width="900"><br>
  <sub>舞台黑金</sub>
</p>

## 它能做什么

- **真·可交互**：侧栏、建议卡、项目选择、输入框都是原生控件，不是整窗假截图贴上去
- **可换图**：换一张喜欢的图，就能变成你的主题
- **可恢复**：一键还原官方外观
- **相对安全**：本机回环 CDP 注入，不改官方二进制与签名

## 快速开始

仓库内按平台放了现成脚本（实现细节不同，效果都是「主题化 Codex」）：

| 平台 | 目录 | 入口 |
|------|------|------|
| Apple Silicon / Intel Mac | [`macos/`](./macos/) | 双击 `Install Codex Dream Skin.command` |
| Windows | [`windows/`](./windows/) | `scripts/install-dream-skin.ps1` → `start-dream-skin.ps1` |

更细的说明：

- Mac：[`macos/README.md`](./macos/README.md)
- Windows：[`windows/SKILL.md`](./windows/SKILL.md)
- 路径对照：[`docs/platforms.md`](./docs/platforms.md)
- 项目记录：[`docs/PROJECT.md`](./docs/PROJECT.md)
- `2.2.8` 跨平台安装验证：[`docs/RELEASE-VALIDATION-v2.2.8.md`](./docs/RELEASE-VALIDATION-v2.2.8.md)

## 反馈与贡献

- **Issue：** 请用 [Issue 模板](./.github/ISSUE_TEMPLATE/)（Bug / 功能）；已关闭空白 Issue。提交前建议先跑 Verify / Restore 自检。
- **PR：** 请按 [PR 模板](./.github/pull_request_template.md) 写清改动，并勾选对应自测（如 `macos/tests/run-tests.sh`、verify / restore）。

## 安全边界

- CDP 只绑 `127.0.0.1`，主题运行期间勿跑来路不明的本机程序
- 不修改官方安装目录与代码签名
- **不会**自动改写 API Key / Base URL；中转与换肤分开

## 许可与声明

- 软件源码采用 [`LICENSE`](./LICENSE)（MIT）
- 人物、角色、QQ 与品牌素材不自动包含在代码许可中，公开分发前请阅读 [`ASSET_RIGHTS.md`](./ASSET_RIGHTS.md)
- 非 OpenAI 官方产品；Codex 及相关权利归其权利人
- 效果图中的人物 / IP 形象仅作主题示意；商用或公开再分发请自行确认肖像权与商标授权

---

Star 一下，然后挑一张图，把你的 Codex 变成今天想要的样子。
