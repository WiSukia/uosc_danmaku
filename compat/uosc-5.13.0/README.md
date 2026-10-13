# uosc 5.13.0 中文输入兼容补丁

来源：<https://github.com/tomasklaen/uosc/tree/5.13.0>，提交 `d124c2c930d69446448022851373e00ae592390d`。

`Menu.lua` 为原项目 `src/uosc/elements/Menu.lua` 的派生文件，仅增加 native input 属性清理、布局发布、焦点命令、文本/选区/组合状态显示及 `native-input-update` 消息。修改整理日期：2026-10-13，维护者 WiSukia。LGPL v2.1 原许可证保留为 `LICENSE.LGPL`。

`native-input.patch` 可在 uosc 5.13.0 源码根目录用 `git apply` 应用。`hashes.json` 是原版与修改版在 CRLF 转 LF 后的 SHA-256。已有个性化改动应合并补丁；自动安装器会拒绝未知文件。此补丁不包含个人播放列表、快捷键、顶栏或通知修改。
