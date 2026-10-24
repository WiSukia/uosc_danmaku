# uosc_danmaku · WiSukia 改版

基于 [Tony15246/uosc_danmaku](https://github.com/Tony15246/uosc_danmaku) **v2.1.0** 的非官方增强版。保留原项目历史与 MIT 许可证，个人改动在 `wisukia-enhanced` 分支；`main` 保留 fork 时的上游内容。此版本整理自实际使用的 Windows / mpv.net 插件，并未迁移上游后续的所有功能和修复。

## 改动

- 弹幕样式菜单支持保存字体、字号、粗体、描边、阴影、透明度、滚动时间、显示区域、折叠开关和刷新目标。
- 相近重复弹幕按固定时间窗口折叠，显示 `× N`。忽略部分标点、空白和英文字母大小写，保留影响数字含义的分隔符；窗口不会随新弹幕延长。这是文本规则匹配。
- 自动屏蔽日期与报到、人数统计、交流群与群号，三类规则默认开启，可分别开关并自动保存。
- 屏蔽菜单最多 12 行，顶部四个操作项固定；下方词条滚动，删除时原地更新并保留滚动位置和搜索。
- 关键词屏蔽支持添加、删除、启用/停用和持久保存，按包含关系匹配，英文忽略大小写。
- Windows 原生中文输入桥接，在 uosc 的屏蔽词菜单中显示输入、选区和输入法组合状态。
- 弹幕使用独立计时器与预测播放时钟刷新，暂停、缓存、跳转、倍速、倒放和卸载时校准。默认目标 60，可设 120 或分数；实际刷新受显示器和性能限制。
- 只移除旧插件自有的 `@danmaku:fps` 视频滤镜。弹幕显示时临时使用 `video-sync=display-resample`，隐藏后恢复；不启用运动插帧。
- 提示使用 mpv 原生 OSD，解除个人 `frame_notice` 依赖；更新入口改为手动更新提示，避免被上游原版覆盖。

## 下载和安装

下载 [Releases](https://github.com/WiSukia/uosc_danmaku/releases) 中的 `uosc_danmaku-v2.1.0-wisukia.2-windows.zip`，并按 `SHA256SUMS.txt` 校验。本版本仍标为预发布，当前验证范围见 [验证记录](docs/VERIFICATION.md)。

1. 关闭播放器，备份已有 `scripts/uosc_danmaku` 和弹幕配置。
2. 解压 ZIP，将 `scripts/uosc_danmaku` 复制到 mpv 配置目录。mpv.net 通常是 `%APPDATA%/mpv.net`；原生 mpv 通常是 `%APPDATA%/mpv`。
3. 创建 `script-opts` 目录。首次安装将 `examples/uosc_danmaku.conf` 复制为 `script-opts/uosc_danmaku.conf`；已有配置请合并选项。旧 `vf_fps` 已不再使用，可删除该项。
4. 安装 [uosc 5.13.0](https://github.com/tomasklaen/uosc/releases/tag/5.13.0)。Windows 中文输入和下方弹幕屏蔽菜单布局需要本包中的兼容补丁：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-uosc-compat.ps1 -MpvConfigDirectory "$env:APPDATA\mpv.net"
   ```

   安装脚本接受未修改的 uosc 5.13.0 `Menu.lua` 或本仓库首版兼容补丁，可自动升级旧补丁，会备份并回读。已有修改或其他版本会停止，请自行合并 `compat/uosc-5.13.0/native-input.patch`。不要直接覆盖其他定制的 uosc 文件。
5. 重启播放器。默认 `Ctrl+d` 搜索弹幕，`j` 显示/隐藏。继续阅读下方的 [基础使用说明](#基础使用说明)，配置 uosc 控件和可选功能。

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

## 基础使用说明

以下根据 [Tony15246/uosc_danmaku v2.1.0 使用说明](https://github.com/Tony15246/uosc_danmaku/blob/v2.1.0/README.md) 和本分支源码整理，适用于本改版。原项目文档副本保留在 [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md)，供了解原版和历史行为；其中 FPS 滤镜、通知位置、自动更新等旧说明不适用于本改版，以本 README 为准。

### 原项目的基础功能

- 从弹弹play或兼容的自定义服务搜索作品、选择集数并加载弹幕。
- 通过 uosc 控件和菜单搜索、开关弹幕、管理弹幕源、修改样式及调整延迟。
- 加入受支持的网络弹幕源，也可以手动加载本地 XML / ASS 弹幕文件。
- 记录视频与弹幕的关联；开启自动加载后，可在重新播放和识别同目录集数时复用记录。
- 按配置加载同名本地 XML、在本地视频关闭时保存弹幕，以及处理支持的网络播放地址。
- 支持简繁转换、原版重复合并和文件形式的屏蔽规则。

这些是继承的功能，具体网站、API 和网络地址能否使用取决于对应服务。本改版新增的折叠、关键词菜单和独立刷新见上方 [改动](#改动)。

### 运行依赖与目录

推荐使用带 uosc 的 mpv / mpv.net。通过 `mp.input` 使用部分基础菜单时，按原项目要求需 mpv 0.39.0 或以上；本改版的 Windows 原生中文输入依赖上方指定的 uosc 兼容补丁。哈希匹配还依赖 LuaJIT 或 Lua 5.2，单纯通过 Lua 5.1 语法检查不代表哈希功能可用。

HTTP 请求需要播放器进程能找到 `curl`。安装后保持脚本文件夹名为 `uosc_danmaku`，因为控件、配置和消息都使用这个名称。配置目录的主要结构如下：

```text
mpv 配置目录/
├── input.conf
├── script-opts/
│   ├── uosc.conf
│   └── uosc_danmaku.conf
└── scripts/
    ├── uosc/
    └── uosc_danmaku/
        ├── main.lua
        ├── apis/
        ├── dicts/
        ├── modules/
        ├── LICENSE
        ├── UoscInputBridge.cs
        └── UoscInputBridge.exe
```

最后两个文件用于 Windows 输入助手。`input.conf` 管理快捷键，`uosc.conf` 管理播放器控件，`uosc_danmaku.conf` 管理弹幕选项；不要把三个文件的配置混在一起。

### uosc 控件配置

编辑 `script-opts/uosc.conf` 中已有的 `controls=`，把需要的弹幕控件插入逗号分隔的控件列表，保留原来的控件。本例采用 uosc 的 `command:` 写法，向指定的弹幕脚本发送消息。

| 功能 | 加入 `controls` 的内容 |
| --- | --- |
| 搜索弹幕 | `command:search:script-message-to uosc_danmaku open_search_danmaku_menu?搜索弹幕` |
| 弹幕开关 | `cycle:toggle_on:show_danmaku@uosc_danmaku:on=toggle_on/off=toggle_off?弹幕开关` |
| 添加弹幕源 | `command:add_box:script-message-to uosc_danmaku open_add_source_menu?从源添加弹幕` |
| 弹幕样式 | `command:palette:script-message-to uosc_danmaku open_danmaku_style_menu?弹幕样式` |
| 弹幕设置 | `command:grid_view:script-message-to uosc_danmaku open_add_total_menu?弹幕设置` |
| 弹幕源延迟 | `command:more_time:script-message-to uosc_danmaku open_source_delay_menu?弹幕源延迟` |

例如，下面是包含搜索、开关、样式和设置入口的一套完整示例。已有自定义控件时请合并需要的条目。

```ini
controls=menu,gap,subtitles,<has_many_audio>audio,<has_many_video>video,<has_many_edition>editions,<stream>stream-quality,command:search:script-message-to uosc_danmaku open_search_danmaku_menu?搜索弹幕,cycle:toggle_on:show_danmaku@uosc_danmaku:on=toggle_on/off=toggle_off?弹幕开关,command:palette:script-message-to uosc_danmaku open_danmaku_style_menu?弹幕样式,command:grid_view:script-message-to uosc_danmaku open_add_total_menu?弹幕设置,gap,space,speed,space,shuffle,loop-playlist,loop-file,gap,prev,items,next,gap,fullscreen
```

没有添加控件时，仍可用快捷键调用相应功能。改版关键词屏蔽入口在弹幕设置菜单内，也可以用下方消息直接打开。

### 快捷键与脚本消息

默认 `Ctrl+d` 搜索，`j` 显示/隐藏弹幕。如果在 `input.conf` 中明确绑定了同一个按键，以该文件的绑定为准。

下面是一套可选绑定，复制前检查是否与自己的按键冲突：

```text
Ctrl+d script-message-to uosc_danmaku open_search_danmaku_menu
j script-message-to uosc_danmaku show_danmaku_keyboard
Ctrl+Shift+d script-message-to uosc_danmaku open_add_total_menu
Ctrl+Shift+s script-message-to uosc_danmaku open_danmaku_style_menu
Ctrl+Shift+b script-message-to uosc_danmaku danmaku-blocklist-open
```

也可以在 `script-opts/uosc_danmaku.conf` 中更改插件提供的两个默认键：

```ini
open_search_danmaku_menu_key=Ctrl+d
show_danmaku_keyboard_key=j
```

其余可用消息如下。`KEY` 是示意占位符，使用时替换成自己的按键。

| 功能 | `input.conf` 示例 |
| --- | --- |
| 添加或管理弹幕源 | `KEY script-message-to uosc_danmaku open_add_source_menu` |
| 打开各源延迟菜单 | `KEY script-message-to uosc_danmaku open_source_delay_menu` |
| 给整体弹幕增加 0.5 秒延迟 | `KEY script-message-to uosc_danmaku danmaku-delay 0.5` |
| 给整体弹幕减少 0.5 秒延迟 | `KEY script-message-to uosc_danmaku danmaku-delay -0.5` |
| 保存当前弹幕为 XML | `KEY script-message-to uosc_danmaku immediately_save_danmaku` |
| 清除当前视频的弹幕源关联 | `KEY script-message-to uosc_danmaku clear-source` |
| 显示改版手动更新提示 | `KEY script-message-to uosc_danmaku check-update` |

手动保存限本地视频，输出到视频目录下的同名 XML，现有同名文件可能被覆盖。网络视频不支持这项保存方式。清除源关联会修改当前视频的弹幕关联记录。

### 自动加载与弹幕源

在 `script-opts/uosc_danmaku.conf` 中按需开启：

```ini
# 复用视频关联记录，识别同目录剧集，并尝试哈希匹配
auto_load=yes
# 自动加载视频旁边的同名 XML
autoload_local_danmaku=yes
# 对受支持的网络视频地址尝试自动加载与关联
autoload_for_url=yes
# 本地视频关闭时自动保存同名 XML
save_danmaku=yes
```

这四项代码默认均为 `no`，不必全部开启。自动加载还受记忆的弹幕开关状态影响；没有显示弹幕时先按 `j` 开启。

同目录剧集自动关联依赖文件名的集数识别，建议每个目录只放同一作品。关联错误时重新搜索并选择正确集数。启用同名 XML 自动加载后，它会优先于其他自动加载方式；希望重新获取在线弹幕时，可先关闭该选项或移走旧 XML。

在“从源添加弹幕”中可填写受支持的视频页面地址或本地 XML / ASS 的绝对路径。例如：

```text
https://www.bilibili.com/video/BV1kx411o7Yo
C:\Videos\episode01.xml
```

地址解析和弹幕内容来自第三方服务，示例不保证当前可访问。多个来源的偏移可在“弹幕源延迟”中分别设置。原版 `add_from_source` 选项已经废除，不需要再添加它。

### 自动屏蔽与列表操作

在“弹幕设置 → 弹幕屏蔽 → 自动屏蔽规则”中分别开关日期与报到、人数统计、交流群与群号。“启用屏蔽”总开关同时控制手动词与自动规则。旧版 JSON 没有 `auto` 字段时，三类默认开启；首次切换或编辑屏蔽词会保存新字段，不清空旧词。

这些是本地文字规则，不联网，也不调用 AI：日期规则识别完整日期和有限的签到、报到等前后缀，并校验年月日；人数规则匹配整条统计格式；群号规则要求群相关词和 5～12 位数字，或明确的加群招募短语。支持全角数字及部分空格、分隔符变体，不能覆盖所有广告变体。

关闭某类自动规则不会停用手动词；过宽的手动词仍可能误伤。界面可以分别开关三类，但不能编辑自动匹配条件。个人设置保存在 `script-opts/uosc_danmaku-blocklist.json`，不包含在发布包中。日期和人数的普通剧情语句通常保留。

更新后重新运行 uosc 兼容补丁安装器。屏蔽列表顶部“返回、添加、启用屏蔽、自动屏蔽规则”四行固定，下方词条滚动；点击删除不会关闭重开弹窗，搜索和滚动位置保留，到达末尾时只做必要的滚动范围调整。

### 常用弹幕配置

除菜单保存外，也可直接编辑 `script-opts/uosc_danmaku.conf`，重启播放器使文件中的设置生效。下表为**代码默认值**；发布包示例另外设置了 API 代理并开启改版折叠。

| 配置项 | 代码默认值 | 用途 |
| --- | --- | --- |
| `api_server` | `https://api.dandanplay.net` | 弹弹play兼容服务地址；发布示例使用原项目代理 |
| `fallback_server` | `https://api.danmu.icu` | 部分非动画弹幕的兜底服务 |
| `proxy` | 空 | HTTP 请求代理，按自己的网络环境填写 |
| `cookie_file` | 空 | 可选 Cookie 文件路径，不要提交到仓库 |
| `fps` | `60` | 弹幕独立刷新目标，支持 `120`、`60000/1001` 等数值 |
| `fontname` | `sans-serif` | 系统已安装的字体名；Windows 可尝试 `Microsoft YaHei` |
| `fontsize` / `bold` | `50` / `yes` | 字号与粗体 |
| `outline` / `shadow` | `1` / `0` | 描边与阴影 |
| `scrolltime` / `fixtime` | `15` / `5` | 滚动 / 固定弹幕的显示秒数 |
| `opacity` | `0.7` | 透明度，0 完全透明，1 不透明 |
| `displayarea` | `0.85` | 可显示区域占画面高度的比例 |
| `merge_screen_duplicates` | `no` | 开启改版的相近文本折叠；发布示例为 `yes` |
| `merge_window` | `15` | 改版折叠的固定时间窗口，实际还受弹幕显示时长限制 |
| `merge_tolerance` | `-1` | 原版重复合并时间容差；改版折叠开启时走改版规则 |
| `max_screen_danmaku` | `0` | 同时显示的弹幕数量上限，0 不限制 |
| `chConvert` | `0` | 0 不转换，1 转简体，2 转繁体 |
| `blacklist_path` | 空 | 继承的屏蔽规则文件路径，与关键词菜单保存的 JSON 分开 |
| `history_path` | `~~/danmaku-history.json` | 弹幕关联与显示状态记录路径 |

`~~/` 表示播放器配置目录。关键词菜单按文本包含关系匹配；原版 `blacklist_path` 支持的规则与文件格式见 [原项目文档副本](docs/UPSTREAM_README.md)。

`fps` 不再提高视频帧率，旧 `vf_fps` 不生效。实际弹幕刷新取决于显示器与设备性能。提示已改为 mpv 原生 OSD，旧 `message_x`、`message_y`、`message_anlignment` 不再控制提示位置。

### 常见问题

**控件不显示，或快捷键没有反应**

检查 `scripts/uosc_danmaku/main.lua` 是否存在、是否多套了一层解压目录、脚本文件夹是否叫 `uosc_danmaku`。控件需要合并到 `uosc.conf` 的 `controls=` 中；快捷键冲突检查 `input.conf`。打开 mpv 控制台查看加载错误。

**搜索失败或出现 HTTP 请求错误**

先确认播放器能找到 `curl`，再查看控制台中的具体错误。检查 `api_server`、代理和必要的 Cookie 路径，以及服务是否可访问。网络错误不一定是插件本身的问题；不要通过覆盖安装当前上游来解决，以免丢失改版功能。

本分支的弹幕 JSON API 请求使用 5 秒连接超时、12 秒单次总超时。遇到暂时性连接失败或 HTTP 5xx 时，等待 1 秒后重试一次；若使用作者的 `https://danmaku-api.152468.xyz` 或 `https://danmaku-us.152468.xyz`，仍失败会切换到另一个等价接口，再允许重试一次，总共最多四次尝试。成功的接口优先使用 60 秒。HTTP 429 等客户端错误不会触发重试或切换，自定义服务器也不会转发到作者接口。

搜索及选择集数异步执行；重新搜索、关闭菜单或切换视频会取消旧请求。控制台中的 `API request failed` 会标明接口地址、curl 返回码和 HTTP 状态，新增诊断不输出查询参数、文件哈希或响应正文。网络请求全部失败后会停止本次自动匹配；哈希查询正常返回但未匹配时，仍会尝试文件名匹配。

**匹配到错误作品、缺少弹幕或时间对不上**

手动搜索并选择正确集数，必要时添加其他受支持的弹幕源，在延迟菜单中调整偏移。同目录混放作品或集数识别失败可能影响自动关联。弹幕库内容由各来源维护；需要完善公共来源时，可参考 [弹弹play](https://www.dandanplay.com/) 和 [原项目关于弹幕源的说明](docs/UPSTREAM_README.md#常见问题)。

**中文输入不可用**

检查 `UoscInputBridge.exe` 是否存在，并确认 uosc 5.13.0 已合并本仓库的中文输入补丁。自动安装器拒绝未知 `Menu.lua` 是为了保护已有修改；这时应手动合并补丁。真实输入法的候选词和组合输入仍在待验证范围内。

**样式或屏蔽词无法保存**

确认配置目录下存在可写的 `script-opts` 目录。样式写入 `uosc_danmaku.conf`，菜单屏蔽词写入 `uosc_danmaku-blocklist.json`；不要误把播放器目录中的同名示例当成实际配置。损坏的屏蔽词 JSON 会阻止保存，先备份并检查文件。

**如何更新，为什么不再自动下载**

从本仓库 [Releases](https://github.com/WiSukia/uosc_danmaku/releases) 下载，备份后按上方步骤更新；`check-update` 只给出手动更新提示。`main` 保留的是 fork 时的原项目内容，使用改版源码请选 `wisukia-enhanced`。

## 来源与致谢

感谢 [Tony15246/uosc_danmaku](https://github.com/Tony15246/uosc_danmaku) 原作者与贡献者提供基础插件、使用说明和实现。本 README 后半部分在原项目 v2.1.0 文档基础上整理，并根据本分支行为修订；它不代表当前上游所有功能都已合并。

保留原项目对以下项目的致谢：

- 弹幕 API：[弹弹play](https://github.com/kaedei/dandanplay-libraryindex/blob/master/api/OpenPlatform.md)
- 菜单 UI：[uosc](https://github.com/tomasklaen/uosc)
- 弹幕格式转换参考：[DanmakuConvert](https://github.com/timerring/DanmakuConvert)
- 简繁转换参考：[OpenCC](https://github.com/BYVoid/OpenCC)
- Lua MD5 实现参考：[rkscv/danmaku](https://github.com/rkscv/danmaku)
- B 站弹幕实现参考：[MPV-Play-BiliBili-Comments](https://github.com/itKelis/MPV-Play-BiliBili-Comments)
- 巴哈姆特弹幕实现参考：[MPV-Play-BAHA-Comments](https://github.com/s594569321/MPV-Play-BAHA-Comments)

原项目文档还列出了相关 fork：[slqy123/uosc_danmaku](https://github.com/slqy123/uosc_danmaku) 与 [Loukyuu1120/uosc_danmaku](https://github.com/Loukyuu1120/uosc_danmaku)。它们的功能和支持范围以各自仓库说明为准。

## 许可证

弹幕插件及新增助手源码遵循根目录 [MIT LICENSE](LICENSE)，保留 Tony 的版权声明。`compat/uosc-5.13.0/Menu.lua` 来自 tomasklaen/uosc 5.13.0，加入中文输入桥接和弹幕屏蔽菜单修改，遵循该项目的 [LGPL v2.1](compat/uosc-5.13.0/LICENSE.LGPL)。该目录附补丁、校验与来源说明；根目录 MIT 不覆盖 uosc 派生文件。
