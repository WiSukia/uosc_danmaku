# uosc_danmaku · WiSukia 改版

基于 [Tony15246/uosc_danmaku](https://github.com/Tony15246/uosc_danmaku) **v2.1.0** 的非官方增强版。保留原项目历史与 MIT 许可证，个人改动在 `wisukia-enhanced` 分支；`main` 保留 fork 时的上游内容。此版本整理自实际使用的 Windows / mpv.net 插件，并未迁移上游后续的所有功能和修复。

## 改动

- 弹幕样式菜单支持保存字体、字号、粗体、描边、阴影、透明度、滚动时间、显示区域、折叠开关和刷新目标。
- 相近重复弹幕按固定时间窗口折叠，显示 `× N`。忽略部分标点、空白和英文字母大小写，保留影响数字含义的分隔符；窗口不会随新弹幕延长。这是文本规则匹配。
- 关键词屏蔽支持添加、删除、启用/停用和持久保存，按包含关系匹配，英文忽略大小写。
- Windows 原生中文输入桥接，在 uosc 的屏蔽词菜单中显示输入、选区和输入法组合状态。
- 弹幕使用独立计时器与预测播放时钟刷新，暂停、缓存、跳转、倍速、倒放和卸载时校准。默认目标 60，可设 120 或分数；实际刷新受显示器和性能限制。
- 只移除旧插件自有的 `@danmaku:fps` 视频滤镜。弹幕显示时临时使用 `video-sync=display-resample`，隐藏后恢复；不启用运动插帧。
- 提示使用 mpv 原生 OSD，解除个人 `frame_notice` 依赖；更新入口改为手动更新提示，避免被上游原版覆盖。

## 下载和安装

下载 [Releases](https://github.com/WiSukia/uosc_danmaku/releases) 中的 `uosc_danmaku-v2.1.0-wisukia.1-windows.zip`，并按 `SHA256SUMS.txt` 校验。首次发布标为预发布，当前验证范围见 [验证记录](docs/VERIFICATION.md)。

1. 关闭播放器，备份已有 `scripts/uosc_danmaku` 和弹幕配置。
2. 解压 ZIP，将 `scripts/uosc_danmaku` 复制到 mpv 配置目录。mpv.net 通常是 `%APPDATA%/mpv.net`；原生 mpv 通常是 `%APPDATA%/mpv`。
3. 创建 `script-opts` 目录。首次安装将 `examples/uosc_danmaku.conf` 复制为 `script-opts/uosc_danmaku.conf`；已有配置请合并选项。旧 `vf_fps` 已不再使用，可删除该项。
4. 安装 [uosc 5.13.0](https://github.com/tomasklaen/uosc/releases/tag/5.13.0)。Windows 中文输入还需要本包中的兼容补丁：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-uosc-compat.ps1 -MpvConfigDirectory "$env:APPDATA\mpv.net"
   ```

   安装脚本仅接受未修改的 uosc 5.13.0 `Menu.lua`，会备份并回读。已有修改或其他版本会停止，请自行合并 `compat/uosc-5.13.0/native-input.patch`。不要直接覆盖其他定制的 uosc 文件。
5. 重启播放器。默认 `Ctrl+d` 搜索弹幕，`j` 显示/隐藏。uosc 控件、依赖 `curl` 等原有安装方式见 [上游使用说明](docs/UPSTREAM_README.md)。

ZIP 中的输入助手由仓库 `UoscInputBridge.cs` 编译；不含个人播放历史、屏蔽词、Cookie、代理设置或播放器完整配置。关键词会保存到用户配置目录的 `script-opts/uosc_danmaku-blocklist.json`，历史记录默认保存为 `danmaku-history.json`。

## 从源码使用

切换到 `wisukia-enhanced` 分支。将 `main.lua`、`apis/`、`dicts/`、`modules/` 放入 `scripts/uosc_danmaku`。Windows 还需将 `UoscInputBridge.cs` 放入该目录并运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-helper.ps1
```

然后复制生成的 `UoscInputBridge.exe`，并按安装步骤添加配置和 uosc 兼容补丁。需要 Windows .NET Framework 4.x；源码不跟踪生成的 EXE。

## 更新、服务与支持范围

本 fork 手动从 Release 更新；插件内的 `check-update` 只提示下载位置。通用示例使用原项目提供的代理服务，源码仍保留 v2.1.0 的 API 实现和默认值；服务来源、限制和可用性依赖各提供方。未加入私人凭据；继承的 API 常量与 v2.1.0 一致。

当前本次验证包括 Lua 5.1 语法与行为模拟、干净安装目录下的隔离 libmpv 运行，以及 C# 编译、补丁和包结构检查。模拟和隔离运行不能保证真实窗口的持续播放表现，也不证明真实输入法候选词交互。Linux/macOS 与真实中文输入法需进一步验证。

## 许可证

弹幕插件及新增助手源码遵循根目录 [MIT LICENSE](LICENSE)，保留 Tony 的版权声明。`compat/uosc-5.13.0/Menu.lua` 来自 tomasklaen/uosc 5.13.0，仅加入中文输入桥接修改，遵循该项目的 [LGPL v2.1](compat/uosc-5.13.0/LICENSE.LGPL)。该目录附补丁、校验与来源说明；根目录 MIT 不覆盖 uosc 派生文件。
