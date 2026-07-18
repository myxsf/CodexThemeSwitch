# GitHub 上传说明

目标仓库：`https://github.com/myxsf/CodexThemeSwitch`

## 1. 登录

先确认 GitHub CLI 已登录：

```bash
gh auth login -h github.com
gh auth status
```

登录步骤需要你本人在浏览器确认，且不要把 token 发给任何人。

## 2. 从发布目录建库

在 `source/` 目录执行：

```bash
git init -b main
git add .
git commit -m "Keep light themes readable inside Codex dark shell"
gh repo create myxsf/CodexThemeSwitch --public --source=. --remote=origin --push
```

## 3. 上传 Release

仓库推送完成后，在本发布目录执行：

```bash
gh release create v2.2.9 \
  release/Codex-Theme-Wardrobe-v2.2.9-macos-universal.zip \
  release/Codex-Theme-Wardrobe-v2.2.9-windows.zip \
  release/Codex-Theme-Wardrobe-v2.2.9-background-assets.zip \
  release/SHA256SUMS.txt \
  --repo myxsf/CodexThemeSwitch \
  --title "Codex Theme Wardrobe 2.2.9" \
  --notes-file release/README.zh-CN.md
```

## 发布前权利检查

先阅读 `source/ASSET_RIGHTS.md`。人物、角色、QQ 和品牌素材是
`review-required`，代码的 MIT 许可证不会自动授予这些素材的再分发权。
