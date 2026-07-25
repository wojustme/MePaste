# MePaste

一个原生 macOS 剪贴板历史工具，使用 `Shift + Command + V` 快速查看并恢复历史内容。

支持 macOS 13 及以上系统，以及 Apple Silicon 与 Intel Mac。

## 功能

- 监听并保存文本、图片、富文本、文件 URL 等剪贴板格式
- 使用 `⇧⌘V` 在任意应用中打开历史面板
- 横向滚动、左右方向键切换，点击或按 Return 恢复记录
- 按最长保留天数和最大记录数两个维度自动清理
- 菜单栏常驻，可进入设置或退出
- 支持登录时自动启动
- 可在设置中录制并持久化全局快捷键
- 状态栏菜单可直接查看记录数、切换开机启动及进入容量设置
- 历史面板自动适配当前显示器宽度并紧贴屏幕底边
- 状态栏菜单使用独立设置窗口管理启动项、快捷键和历史容量
- 打包为同时支持 Apple Silicon 和 Intel 的 Universal 2 应用

## 开发运行

```bash
swift run MePaste
```

## 打包应用

```bash
./scripts/build-app.sh
open build/MePaste.app
```

打包产物同时包含 `arm64` 和 `x86_64` 架构。建议将 `MePaste.app` 移至 `/Applications` 后，再在设置中启用“登录时自动启动”。

## 打包 DMG

```bash
./scripts/build-dmg.sh
open build/MePaste.dmg
```

DMG 中包含 `MePaste.app` 和 `/Applications` 快捷入口。

## Homebrew 安装与发布

发布版将通过个人 Tap 分发。

用户安装：

```bash
brew install --cask wojustme/tap/mepaste
```

维护者发布一个版本：

1. 更新 `Resources/Info.plist` 中的 `CFBundleShortVersionString` 和 `CFBundleVersion`，例如 `0.0.1` 和 `1`。
2. 创建并推送同名 Git tag：

   ```bash
   git tag v0.0.1
   git push origin v0.0.1
   ```

   GitHub Actions 会构建 `MePaste-v0.0.1.dmg`、计算 SHA-256，并创建对应的 GitHub Release。
3. 检出（首次创建即可）个人 Tap 仓库：

   ```bash
   git clone git@github.com:wojustme/homebrew-tap.git ../homebrew-tap
   ```

4. 从 Release 工作流日志或 Release 附件 `MePaste-v0.0.1.dmg.sha256` 取得哈希值，并更新 cask：

   ```bash
   ./scripts/update-homebrew-cask.sh \
     --version 0.0.1 \
     --sha256 <MePaste-v0.0.1.dmg 的 SHA-256> \
     --tap-dir ../homebrew-tap

   brew audit --cask --strict ../homebrew-tap/Casks/mepaste.rb
   git -C ../homebrew-tap add Casks/mepaste.rb
   git -C ../homebrew-tap commit -m "mepaste 0.0.1"
   git -C ../homebrew-tap push
   ```

对于尚未推送 tag 的本地验收，可执行 `./scripts/prepare-release.sh 0.0.1`，发布文件和校验和将生成在 `build/release/`。

## 许可证

本项目采用 [MIT License](LICENSE)。

应用图标源文件为 `Resources/AppIcon.png`，打包时会自动生成 macOS 多尺寸 `AppIcon.icns`。

应用数据保存在 `~/Library/Application Support/MePaste/history.json`。
