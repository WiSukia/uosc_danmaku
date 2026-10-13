-- This fork is updated manually to preserve local enhancements and user settings.
local msg = require('mp.msg')
function check_for_update()
    local text = "WiSukia 改版请从 GitHub Release 手动更新；不会覆盖当前插件。"
    show_message(text, 5)
    msg.info(text .. " https://github.com/WiSukia/uosc_danmaku/releases")
end
