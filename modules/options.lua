local opt = require("mp.options")

-- 选项
options = {
    -- 指定弹幕服务器地址，自定义服务需兼容 dandanplay 的 api
    api_server = "https://api.dandanplay.net",
    -- 指定 b 站和爱腾优的弹幕获取的兜底服务器地址，主要用于获取非动画弹幕
    -- 可用： https://api.danmu.icu，https://dmku.hls.one
    fallback_server = "https://api.danmu.icu",
    -- 设置 tmdb 的 API Key，用于获取非动画条目的中文信息(当搜索内容非中文时)
    -- 可以在 https://www.themoviedb.org 注册后去个人账号设置界面获取
    -- 注意：自定义此参数时还需要对获取到的 API Key 进行 base64 编码
    tmdb_api_key = "NmJmYjIxOTZkNzIyN2UyMTIzMGM3Y2YzZjQ4MDNkZGM=",
    auto_load = false,
    autoload_local_danmaku = false,
    autoload_for_url = false,
    save_danmaku = false,
    user_agent = "mpv_danmaku/1.0",
    proxy = "",
    -- 可选：向 HTTP 请求传递 cookie.txt 文件路径
    cookie_file = "",
    -- 设置弹幕独立刷新目标帧率；默认 60，可填写分数
    fps = "60",
    -- 指定合并重复弹幕的时间间隔的容差值，单位为秒。默认值: -1，表示禁用
    merge_tolerance = -1,
    -- Fold similar comments in a fixed time window before assigning lanes.
    merge_screen_duplicates = false,
    merge_window = 15,
    -- 指定弹幕关联历史记录文件的路径，支持绝对路径和相对路径
    history_path = "~~/danmaku-history.json",
    open_search_danmaku_menu_key = "Ctrl+d",
    show_danmaku_keyboard_key = "j",
    -- 中文简繁转换。0-不转换，1-转换为简体，2-转换为繁体
    chConvert = 0,
    --滚动弹幕的显示时间
    scrolltime = 15,
    --固定弹幕的显示时间
    fixtime = 5,
    --字体
    fontname = "sans-serif",
    --字体大小 
    fontsize = 50,
    --字体阴影
    shadow = 0,
    --字体粗体
    bold = true,
    -- 透明度：0（完全透明）到 1（不透明）
    opacity = 0.7,
    --全部弹幕的显示范围(0.0-1.0)
    displayarea = 0.85,
    --描边 0-4
    outline = 1.0,
    -- 限制屏幕中同时显示的最大弹幕数量，0 表示不限制
    max_screen_danmaku = 0,
    --指定弹幕屏蔽词文件路径(black.txt)，支持绝对路径和相对路径。文件内容以换行分隔
    --支持 lua 的正则表达式写法
    blacklist_path = "",
    --指定脚本相关消息显示的消息的对齐方式
    message_anlignment = 7,
    --指定脚本相关消息显示的消息的x轴坐标
    message_x = 30,
    --指定脚本相关消息显示的消息的y轴坐标
    message_y = 30,
    -- 自定义标题解析中的额外替换规则，内容格式为 JSON 字符串，替换模式为 lua 的 string.gsub 函数
    --! 注意：由于 mpv 的 lua 版本限制，自定义规则只支持形如 %n 的捕获组写法，即示例用法，不支持直接替换字符的写法
    title_replace = [[
       [{ 
           "rules": [{ "^〔(.-)〕": "%1"},{ "^.*《(.-)》": "%1" }],
       }]
    ]],
    -- 指定哈希匹配中需忽略的共享盘（挂载盘）的路径/目录。支持绝对路径和相对路径，多个路径用逗号分隔
    -- 示例：["X:", "Z:", "F:/Download/", "Download"]
    excluded_path = [[
        []
    ]],
}

opt.read_options(options, mp.get_script_name(), function() end)

-- Persist accepted style menu changes in the standard script options file.
local persistent_style_keys = {
    bold = true, fontsize = true, outline = true, shadow = true,
    scrolltime = true, opacity = true, displayarea = true,
    merge_screen_duplicates = true, fps = true, fontname = true,
}
local style_config_path = mp.command_native({
    "expand-path", "~~/script-opts/" .. mp.get_script_name() .. ".conf"
})


function normalize_danmaku_fps(value)
    if type(value) ~= "string" and type(value) ~= "number" then return end
    local text = tostring(value):gsub("%s", "")
    local numerator, denominator = text:match("^(%d+%.?%d*)/(%d+%.?%d*)$")
    local rate
    if numerator then
        denominator = tonumber(denominator)
        if denominator <= 0 then return end
        rate = tonumber(numerator) / denominator
    elseif text:match("^%d+%.?%d*$") then
        rate = tonumber(text)
    end
    if not rate or rate < 1 or rate > 1000 then return end
    return text
end

function normalize_danmaku_font(value)
    if type(value) ~= "string" then return end
    local text = value:match("^%s*(.-)%s*$")
    -- Names are written to one config line and inserted into an ASS font tag.
    if text == "" or #text > 256 or text:find("[%c\\{}#]") then return end
    return text
end

function save_danmaku_style_option(key)
    if not persistent_style_keys[key] then return end
    local value = options[key]
    if key == "fontname" then
        value = normalize_danmaku_font(value)
        if not value then return end
    elseif key == "fps" then
        value = normalize_danmaku_fps(value)
        if not value then return end
    elseif type(value) == "boolean" then
        value = value and "yes" or "no"
    else
        value = tonumber(value)
        if not value or value ~= value or math.abs(value) == math.huge then return end
        value = tostring(value)
    end

    local function report_error(reason)
        mp.msg.error("Unable to save danmaku style: " .. tostring(reason))
        mp.osd_message("弹幕设置保存失败，请检查配置文件权限")
    end

    local input, err, code = io.open(style_config_path, "rb")
    local contents = ""
    if input then
        local read_err
        contents, read_err = input:read("*a")
        input:close()
        if not contents then report_error(read_err); return end
    elseif code ~= 2 then
        -- Only a missing file may be created; never overwrite an unreadable file.
        report_error(err)
        return
    end

    local newline = contents:find("\r\n", 1, true) and "\r\n" or "\n"
    local normalized = contents:gsub("\r\n", "\n")
    if normalized ~= "" and normalized:sub(-1) ~= "\n" then normalized = normalized .. "\n" end
    local lines, found = {}, false
    for line in normalized:gmatch("(.-)\n") do
        local updated_line = line
        if line:match("^%s*" .. key .. "%s*=") then
            local comment = line:match("(%s+#.*)$") or ""
            updated_line = key .. "=" .. value .. comment
            found = true
        end
        lines[#lines + 1] = updated_line
    end
    if not found then lines[#lines + 1] = key .. "=" .. value end
    local updated = table.concat(lines, newline) .. newline
    if updated == contents then return end

    local output, open_err = io.open(style_config_path, "wb")
    if not output then report_error(open_err); return end
    local written, write_err = output:write(updated)
    local closed, close_err = output:close()
    if not written or not closed then report_error(write_err or close_err) end
end
