# MePaste

一个原生 macOS 剪贴板历史工具，使用 `Shift + Command + V` 快速查看并恢复历史内容。

支持 macOS 13 及以上系统，以及 Apple Silicon 与 Intel Mac。

## 功能

- 监听并保存文本、图片、富文本、文件 URL 等剪贴板格式
- 使用 `⇧⌘V` 在任意应用中打开历史面板
- 在历史面板中搜索文本、文件名和剪贴板类型
- 横向滚动、左右方向键切换，点击或按 Return 恢复记录
- 按最长保留天数和最大记录数两个维度自动清理
- 菜单栏常驻，可进入设置或退出
- 支持登录时自动启动
- 可在设置中录制并持久化全局快捷键
- 状态栏菜单可直接查看版本号与记录数、切换开机启动及进入容量设置
- 历史面板自动适配当前显示器宽度并紧贴屏幕底边
- 状态栏菜单使用独立设置窗口管理启动项、快捷键和历史容量
- 打包为同时支持 Apple Silicon 和 Intel 的 Universal 2 应用

## 开发运行

```bash
swift run MePaste
```

编译与回归测试：

```bash
swift build
swift test
```

测试使用独立的临时目录、偏好设置和剪贴板，不会修改现有历史或系统剪贴板。
覆盖搜索取消、键盘选择、容量清理、富文本/多条目恢复、旧数据格式兼容及图片缩略图缓存。

历史搜索在后台执行，并对连续输入进行短暂防抖。卡片只渲染有限长度的文本预览和按需生成的缩略图；复制和搜索仍使用完整内容。关闭历史面板后会释放其视图，不在后台持续刷新隐藏卡片。

## 版本号

菜单底部（“退出 MePaste”上方）会显示当前构建的版本：

- **本地构建**：`dev-<短 commit ID>`，例如 `dev-a79edc7`。适用于 `swift build`、`swift run` 及本地打包的 APP/DMG；即使使用 `-c release` 或检出发布 tag，也仍是开发版。
- **GitHub Release**：显示完整的发布 tag，例如 `v0.0.4`。打包时校验 tag 与 `CFBundleShortVersionString` 一致，再写入应用元数据；不匹配时构建失败。

Commit ID 由 SwiftPM 构建插件嵌入，增量构建也会跟随 HEAD 更新。安装后的应用不需要 Git 或源码目录，也不会在打开菜单时执行 Git。没有 Git 元数据的源码归档会明确显示 `dev-unknown`。

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

DMG 中包含 `MePaste.app` 和 `/Applications` 快捷入口。每次打包都会先增量构建应用，避免复用旧版本或错误渠道的 APP。

## Homebrew 安装与发布

发布版将通过个人 Tap 分发。

用户安装：

```bash
brew install --cask wojustme/tap/mepaste
```

维护者发布一个版本：

1. 更新 `Resources/Info.plist` 中的 `CFBundleShortVersionString` 和 `CFBundleVersion`，例如 `0.0.2` 和 `2`。
2. 在 `docs/releases/` 中新增对应 tag 的发布说明，例如 `docs/releases/v0.0.2.md`。
3. 创建并推送同名 Git tag：

   ```bash
   git tag v0.0.2
   git push origin v0.0.2
   ```

   GitHub Actions 会构建 `MePaste-v0.0.2.dmg`、计算 SHA-256，并创建对应的 GitHub Release。
4. 检出（首次创建即可）个人 Tap 仓库：

   ```bash
   git clone git@github.com:wojustme/homebrew-tap.git ../homebrew-tap
   ```

5. 从 Release 工作流日志或 Release 附件 `MePaste-v0.0.2.dmg.sha256` 取得哈希值，并更新 cask：

   ```bash
   ./scripts/update-homebrew-cask.sh \
     --version 0.0.2 \
     --sha256 <MePaste-v0.0.2.dmg 的 SHA-256> \
     --tap-dir ../homebrew-tap

   brew audit --cask --strict ../homebrew-tap/Casks/mepaste.rb
   git -C ../homebrew-tap add Casks/mepaste.rb
   git -C ../homebrew-tap commit -m "mepaste 0.0.2"
   git -C ../homebrew-tap push
   ```

对于尚未推送 tag 的本地验收，可执行 `./scripts/prepare-release.sh`，使用 `Info.plist` 中的版本命名产物，文件和校验和将生成在 `build/release/`。也可以显式传入相同的版本号；不一致时会报错。本地生成的应用菜单仍显示 `dev-<短 commit ID>`，只有 GitHub tag 发布流程生成的应用显示正式版本。

## 许可证

本项目采用 [MIT License](LICENSE)。

应用图标源文件为 `Resources/AppIcon.png`，打包时会自动生成 macOS 多尺寸 `AppIcon.icns`。

应用数据保存在 `~/Library/Application Support/MePaste/history.json`。
