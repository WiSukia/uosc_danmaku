-- modified from https://github.com/rkscv/danmaku/blob/main/danmaku.lua
local msg = require('mp.msg')
local utils = require("mp.utils")
local unpack = unpack or table.unpack

local osd_width, osd_height, pause = 0, 0, true
local time_pos_observer_active = false
local render_active, cache_paused, seeking, core_idle = false, false, false, true
local anchor_pos, anchor_time, clock_speed = nil, 0, 1
local render_timer

local function clock_running()
    return render_active and ENABLED and COMMENTS ~= nil and not pause
        and not cache_paused and not seeking and not core_idle
end

local function reanchor(pos)
    anchor_pos = pos or mp.get_property_number('time-pos')
    anchor_time = mp.get_time()
    clock_speed = mp.get_property_number('speed', 1)
        * mp.get_property_number('video-speed-correction', 1)
    if mp.get_property('play-direction') == 'backward' then clock_speed = -clock_speed end
end

local function clock_position()
    if not anchor_pos then return end
    local elapsed = clock_running() and math.max(0, mp.get_time() - anchor_time) or 0
    return math.max(0, anchor_pos + elapsed * clock_speed)
end

local function target_fps()
    local text = normalize_danmaku_fps(options.fps) or '60'
    local n, d = text:match('^([^/]+)/([^/]+)$')
    local rate = n and tonumber(n) / tonumber(d) or tonumber(text)
    local display = mp.get_property_number('display-fps', 0)
    -- Requesting more updates than the monitor can present wastes CPU time.
    return display > 0 and math.min(rate, display) or rate
end

local function update_render_timer()
    if render_timer then render_timer:kill() end
    if clock_running() then
        if not anchor_pos then reanchor() end
        if anchor_pos then
            render_timer.timeout = 1 / target_fps()
            render_timer:resume()
        end
    end
end
local overlay = mp.create_osd_overlay('ass-events')

local function realtime_position_text(event, pos, displayarea)
    if not event.move then
        local _, current_y = unpack(event.pos)
        if not current_y or tonumber(current_y) > displayarea then return end
        if event.style ~= "SP" and event.style ~= "MSG" then
            return string.format("{\\an8}%s", event.text)
        else
            return string.format("{\\an7}%s", event.text)
        end
    end

    local x1, y1, x2, y2 = unpack(event.move)
    -- 计算移动的时间范围
    local duration = event.end_time - event.start_time  --mean: options.scrolltime
    local progress = (pos - event.start_time) / duration  -- 移动进度 [0, 1]

    -- 计算当前坐标
    local current_x = tonumber(x1 + (x2 - x1) * progress)
    local current_y = tonumber(y1 + (y2 - y1) * progress)

    -- 移除 \move 标签并应用当前坐标
    local clean_text = event.text:gsub("\\move%(.-%)", "")
    if current_y > displayarea then return end
    if event.style ~= "SP" and event.style ~= "MSG" then
        return string.format("{\\pos(%.1f,%.1f)\\an8}%s", current_x, current_y, clean_text)
    else
        return string.format("{\\pos(%.1f,%.1f)\\an7}%s", current_x, current_y, clean_text)
    end
end

-- Folded events already contain their count and share a single lifetime.
local function collect_active_events(pos, window_start)
    local events = {}
    local lo = binary_search(COMMENTS, window_start, function(item) return item.start_time end)
    for i = lo, #COMMENTS do
        local event = COMMENTS[i]
        if event.start_time > pos then break end
        if event.end_time > pos then events[#events + 1] = event end
    end
    return events
end

function render(pos_arg)
    if COMMENTS == nil then return end

    local pos, err
    if pos_arg == nil then
        pos, err = mp.get_property_number('time-pos')
        if err ~= nil then
            return msg.error(err)
        end
    else
        pos = pos_arg
    end

    if not pos then
        overlay:remove()
        return
    end

    local fontname = options.fontname
    local fontsize = options.fontsize
    local opacity = tonumber(options.opacity)
    local alpha = string.format("%02X", (1 - (opacity or 0)) * 255)

    local width, height = 1920, 1080
    local ratio = osd_width / osd_height
    if width / height < ratio then
        height = width / ratio
        fontsize = options.fontsize - ratio * 2
    end

    local ass_events = {}
    local max_display = math.max(options.scrolltime, options.fixtime)
    local window_start = pos - max_display

    local re_entity = "&#%d+;"
    local re_fs = "\\fs(%d+)"
    local ass_prefix = string.format("{\\rDefault\\fn%s\\fs%d\\c&HFFFFFF&\\alpha&H%s\\bord%s\\shad%s\\b%s\\q2}",
        fontname, fontsize, alpha, options.outline, options.shadow, options.bold and "1" or "0")

    local events = collect_active_events(pos, window_start)
    for _, event in ipairs(events) do
        local text = realtime_position_text(event, pos, height * options.displayarea)
        if text then
            text = text:gsub(re_entity, "")
            if text:match(re_fs) then
                text = text:gsub(re_fs, function(size)
                    local n = tonumber(size) or 0
                    return string.format("\\fs%d", math.floor(n * 1.5))
                end)
            end
            ass_events[#ass_events + 1] = ass_prefix .. text
        end
    end

    overlay.res_x = width
    overlay.res_y = height
    overlay.data = table.concat(ass_events, '\n')
    overlay:update()
end

-- time-pos is a synchronization source, not the high-rate animation clock.
local function time_pos_callback(_, time_pos)
    if not render_active then return end
    if not time_pos then
        anchor_pos = nil
        update_render_timer()
        overlay:remove()
        return
    end
    local predicted = clock_position()
    local source_fps = mp.get_property_number('estimated-vf-fps', 24)
    local tolerance = math.max(0.10, 2 * math.abs(clock_speed) / math.max(1, source_fps))
    if not predicted or not clock_running() or math.abs(time_pos - predicted) > tolerance then
        reanchor(time_pos)
    end
    if not clock_running() then render(time_pos) end
    -- Start after a previously unavailable playback position becomes valid.
    if not predicted then update_render_timer() end
end

local function start_time_observer()
    if not time_pos_observer_active then
        mp.observe_property('time-pos', 'number', time_pos_callback)
        time_pos_observer_active = true
    end
end

local function stop_time_observer()
    if time_pos_observer_active then
        mp.unobserve_property(time_pos_callback)
        time_pos_observer_active = false
    end
end

render_timer = mp.add_periodic_timer(1 / 60, function()
    if not clock_running() then update_render_timer(); return end
    local pos = clock_position()
    if pos then render(pos) end
end)
render_timer:kill()

function render_danmaku(from_menu, no_osd)
    if ENABLED and (from_menu or get_danmaku_visibility()) then
        if not no_osd then
            show_loaded(true)
        end
        mp.commandv("script-message-to", "uosc", "set", "show_danmaku", "on")
        show_danmaku_func()
    else
        show_message("")
        hide_danmaku_func()
    end
end

-- Remove only the old plugin-owned FPS filter; never change other filters.
local function remove_legacy_fps_filter()
    for _, filter in ipairs(mp.get_property_native('vf') or {}) do
        if filter.label == 'danmaku' and filter.name == 'fps' then
            mp.commandv('vf', 'remove', '@danmaku')
            return
        end
    end
end

-- mpv normally defers OSD redraws to the next video frame. Display sync
-- presents retained video frames at monitor cadence, with fresh OSD positions.
-- This changes scheduling, not decoder/filter FPS or interpolation.
local previous_video_sync
local function enable_display_sync()
    local current = mp.get_property('video-sync', 'audio')
    if current and current:match('^display%-') then return end
    if mp.set_property('video-sync', 'display-resample') then
        previous_video_sync = current
    else
        msg.error('Unable to enable display-synchronized danmaku output')
    end
end

local function restore_video_sync()
    if previous_video_sync then
        -- Preserve an explicit sync-mode change made elsewhere while active.
        if mp.get_property('video-sync') == 'display-resample' then
            mp.set_property('video-sync', previous_video_sync)
        end
        previous_video_sync = nil
    end
end

function refresh_danmaku_fps()
    remove_legacy_fps_filter()
    if render_active and ENABLED and COMMENTS ~= nil then enable_display_sync() end
    update_render_timer()
    if render_active and ENABLED and COMMENTS ~= nil then
        render(clock_position() or mp.get_property_number('time-pos'))
    end
end

function show_danmaku_func()
    mp.set_property_bool(HAS_DANMAKU, true)
    set_danmaku_visibility(true)
    render_active = true
    reanchor()
    render()
    start_time_observer()
    refresh_danmaku_fps()
end

function hide_danmaku_func()
    render_active = false
    update_render_timer()
    stop_time_observer()
    anchor_pos = nil
    mp.set_property_bool(HAS_DANMAKU, false)
    set_danmaku_visibility(false)
    overlay:remove()
    remove_legacy_fps_filter()
    restore_video_sync()
end

-- Notifications share the native OSD with frame, seek and speed messages.
function show_message(text, time)
    -- Old plugin cleanup requests must not erase a newer operation's message.
    if not text or text == "" then return end
    mp.osd_message(text:gsub("\\N", "\n"), time or 3)
end

mp.observe_property('osd-width', 'number', function(_, value) osd_width = value or osd_width end)
mp.observe_property('osd-height', 'number', function(_, value) osd_height = value or osd_height end)
local function sync_clock_state()
    reanchor()
    update_render_timer()
    if render_active and ENABLED and COMMENTS ~= nil and anchor_pos and not seeking then
        render(anchor_pos)
    end
end

mp.observe_property('pause', 'bool', function(_, value)
    pause = value ~= false
    sync_clock_state()
end)
mp.observe_property('paused-for-cache', 'bool', function(_, value)
    cache_paused = value == true
    sync_clock_state()
end)
mp.observe_property('seeking', 'bool', function(_, value)
    seeking = value == true
    sync_clock_state()
end)
mp.observe_property('core-idle', 'bool', function(_, value)
    core_idle = value ~= false
    sync_clock_state()
end)
local function sync_clock_rate()
    -- Small display-sync speed corrections must not snap animation back to
    -- the last discrete video timestamp on every frame.
    local pos = clock_position()
    reanchor(pos)
    update_render_timer()
end
mp.observe_property('speed', 'number', sync_clock_rate)
mp.observe_property('video-speed-correction', 'number', sync_clock_rate)
mp.observe_property('play-direction', 'string', sync_clock_rate)
mp.observe_property('display-fps', 'number', function() update_render_timer() end)

mp.register_event('seek', function()
    seeking = true
    update_render_timer()
end)
mp.register_event('playback-restart', function(event)
    if event.error then return msg.error(event.error) end
    seeking = mp.get_property_bool('seeking', false)
    sync_clock_state()
end)
mp.register_event('shutdown', function()
    render_active = false
    update_render_timer()
    stop_time_observer()
    overlay:remove()
    restore_video_sync()
end)

mp.add_hook("on_unload", 50, function()
    COMMENTS, DELAY = nil, 0
    render_active = false
    update_render_timer()
    stop_time_observer()
    anchor_pos = nil
    overlay:remove()
    mp.set_property_native(DELAY_PROPERTY, 0)
    remove_legacy_fps_filter()
    restore_video_sync()

    local files_to_remove = {
        file1 = utils.join_path(DANMAKU_PATH, "temp-" .. PID .. ".mp4"),
    }

    if options.save_danmaku then
        save_danmaku(true)
    end

    for _, file in pairs(files_to_remove) do
        if file_exists(file) then
            os.remove(file)
        end
    end

    DANMAKU = {sources = {}, count = 1}
end)
