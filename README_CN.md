# BarFold

<div align="center">

**把拥挤的 macOS 菜单栏折叠为紧凑的第二行。**

[English](README.md) | 简体中文 | [日本語](README_JA.md)

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![许可证](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![构建 BarFold](../../actions/workflows/build.yml/badge.svg)](../../actions/workflows/build.yml)

</div>

BarFold 是一个原生 macOS 菜单栏整理工具。它会把选中的菜单栏项目移入菜单栏下方紧凑的第二行，主要用于缓解刘海屏和小尺寸显示器的菜单栏空间不足。

## 界面预览

<div align="center">
  <img src="docs/images/settings.png" alt="BarFold 设置界面" width="480">
  <br><br>
  <img src="docs/images/second-row.png" alt="BarFold 第二行" width="330">
</div>

设置中勾选的项目保留在菜单栏第一行，未勾选的项目会移入 BarFold 第二行。

## 主要功能

- 通过 macOS 辅助功能接口自动发现菜单栏项目。
- 将选中的项目收进可折叠第二行，不在第一行留下透明占位。
- 点击 BarFold 状态栏图标展开或收起第二行。
- 点击第二行外部自动收起，也可按 `Esc` 收起。
- 点击第二行项目时打开对应应用或设置页面。
- 在第二行中拖动图标，保持自定义排列顺序。
- 修改选择时设置列表位置保持不变。
- 整理项目时隐藏合成拖动过程，并保持鼠标原来的位置。
- 菜单栏应用启动、重启或登录时分批出现后，自动重新执行已保存的行位置。
- 将 macOS 锁定的“控制中心”和“时钟”保留在第一行。
- 首次启动默认把所有可发现项目移入第二行。
- 支持登录时启动和多显示器坐标转换。
- 始终保留本地轮转诊断日志，便于排查问题。
- 支持跟随系统语言，或手动选择简体中文、繁体中文、英语、日语、韩语、法语、德语和西班牙语。

## 系统要求

- macOS 13 Ventura 或更高版本。
- 需要辅助功能权限以发现和重新排列菜单栏项目。
- 目标菜单栏项目需要提供足够的辅助功能信息。

macOS 没有公开的状态项管理接口。BarFold 需要使用辅助功能事件和 WindowServer 菜单栏窗口信息，因此不适合通过 Mac App Store 分发。

## 安装步骤

1. 从 [GitHub Releases](../../releases/latest) 下载 `BarFold-x.y.z.zip`。
2. 解压后先把 `BarFold.app` 移入 `/Applications`，再授予权限。
3. 打开 BarFold。如果 macOS 阻止运行 ad-hoc 签名版本，请按住 Control 点击应用并选择**打开**，或前往**系统设置 > 隐私与安全性**允许打开。
4. 前往**系统设置 > 隐私与安全性 > 辅助功能**，启用 BarFold。
5. 打开 BarFold 设置，勾选需要保留在第一行的项目；未勾选项目会自动移入第二行。
6. 点击菜单栏中的 BarFold 图标展开或收起第二行。

移动应用位置，或用签名不同的新构建替换应用，可能会导致 macOS 再次请求辅助功能权限。

## 使用方法

### 选择项目所在行

点击第二行右侧的齿轮按钮打开设置，也可以右键点击 BarFold 状态栏图标并选择**设置**。已勾选项目保留在第一行，未勾选项目折叠到第二行。

### 使用第二行

- 单击 BarFold 状态栏图标展开，再次单击即可收起。
- 单击项目可打开对应应用；只有菜单栏界面的应用可能改为打开其偏好设置。
- 左右拖动项目可调整其在第二行中的顺序。
- 点击第二行以外区域或按 `Esc` 可收起。
- 安装、退出或重新排列其他菜单栏应用后，可点击刷新按钮重新扫描。

### 切换语言

打开设置，点击右上角的地球按钮。语言会立即切换，并在下次启动时继续使用。

## 从源码构建

需要 Xcode 16 或 Swift 6 工具链。

```bash
git clone <你的仓库地址>
cd BarFold
chmod +x scripts/package-app.sh scripts/build-release.sh
./scripts/build-release.sh
open dist/BarFold.app
```

发行压缩包会生成在 `outputs/BarFold-<版本号>.zip`。本机存在 Apple Development 证书时会自动使用第一个可用证书，否则使用 ad-hoc 签名。也可以明确指定签名证书：

```bash
BARFOLD_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/build-release.sh
```

## GitHub 自动构建

[`.github/workflows/build.yml`](.github/workflows/build.yml) 已配置好公开仓库所需的自动流程：

- 推送代码和提交 Pull Request 时，以“警告视为错误”的方式编译，打包应用，验证签名和 ZIP，并上传 Actions 构建产物。
- 推送符合 `v*` 格式的标签时，自动创建或更新 GitHub Release，并附加 ZIP。
- 标签必须与 `CFBundleShortVersionString` 一致。例如应用版本为 `0.5.9` 时，标签必须为 `v0.5.9`。

配置 GitHub 远程仓库后，可通过以下命令发布：

```bash
git push origin main
git push origin v0.5.9
```

默认的 GitHub 托管构建使用 ad-hoc 签名。若需要让公开下载版本免除 Gatekeeper 提示，应使用 Developer ID Application 证书，并在默认流程之外增加 Apple 公证步骤。

## 诊断日志

点击设置页右上角的诊断日志按钮，可在 Finder 中显示：

```text
~/Library/Application Support/BarFold/barfold.log
```

日志只保存在本机，BarFold 不会自动上传。当前日志达到 1 MB 后会轮转为 `barfold.previous.log`，仅保留最近两份。

## 已知限制

- “控制中心”和“时钟”由 macOS 锁定，无法移动。
- 少数第三方状态项不会提供足够的辅助功能信息，或会拒绝模拟拖动事件。
- macOS 大版本更新后，BarFold 可能需要进行兼容性适配。
- 第二行点击行为用于打开应用或偏好设置，不会复现每个应用的原生状态菜单。

报告移动或打开失败时，请提供 macOS 版本、BarFold 版本、受影响的应用名称，以及相关诊断日志片段。

## 版权与许可证

Copyright 2026 BarFold contributors.

本项目基于 [Apache License 2.0](LICENSE) 开源。你可以在遵守该许可证条款的前提下使用、修改和分发本项目。
