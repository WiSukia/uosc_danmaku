local mp = require('mp')
local utils = require('mp.utils')
local M = {}
local auto_filter = require('modules/autofilter')
local auto_keys = {'date','people','group'}
local auto_titles = {date='日期与报到', people='人数统计', group='交流群与群号'}
local function default_auto() return {date=true, people=true, group=true} end
local path = mp.command_native({'expand-path', '~~/script-opts/uosc_danmaku-blocklist.json'})
local state, lowered, read_error = {version=1, enabled=true, words={}, auto=default_auto()}, {}, nil

local function read(pathname)
    local f, err, code = io.open(pathname, 'rb')
    if not f then
        if code == 2 then return nil end
        return nil, err
    end
    local text, reason = f:read('*a'); f:close()
    return text, reason
end

function M.reload()
    local text, err = read(path)
    if not text and not err then text, err = read(path .. '.bak') end
    if not text and not err then
        state, lowered, read_error = {version=1, enabled=true, words={}, auto=default_auto()}, {}, nil
        return true
    end
    local parsed = text and utils.parse_json(text:gsub('^\239\187\191', ''))
    if err or not parsed or parsed.version ~= 1 or type(parsed.enabled) ~= 'boolean'
            or type(parsed.words) ~= 'table' then
        read_error = err or '屏蔽词文件内容无效'
        return false
    end
    local auto = default_auto()
    if parsed.auto ~= nil then
        if type(parsed.auto) ~= 'table' then read_error='自动屏蔽设置无效'; return false end
        for _, key in ipairs(auto_keys) do
            if parsed.auto[key] ~= nil then
                if type(parsed.auto[key]) ~= 'boolean' then read_error='自动屏蔽设置无效'; return false end
                auto[key] = parsed.auto[key]
            end
        end
    end
    local words, keys, seen = {}, {}, {}
    for _, word in ipairs(parsed.words) do
        if type(word) ~= 'string' or word == '' then read_error='屏蔽词文件内容无效'; return false end
        local key = word:lower()
        if not seen[key] then
            words[#words+1], keys[#keys+1], seen[key] = word, key, true
        end
    end
    state, lowered, read_error = {version=1, enabled=parsed.enabled, words=words, auto=auto}, keys, nil
    return true
end

function M.matches(text)
    if not state.enabled then return false end
    text = tostring(text or ''):lower()
    for _, word in ipairs(lowered) do
        if text:find(word, 1, true) then return true, 'word' end
    end
    return auto_filter.matches(text, state.auto)
end

local function save(next_state)
    local text = utils.format_json(next_state)
    if not text then return false, '无法保存屏蔽词' end
    local tmp, backup = path .. '.tmp', path .. '.bak'
    local f, err = io.open(tmp, 'wb')
    if not f then return false, err end
    local ok, write_err = f:write(text .. '\n')
    local closed, close_err = f:close()
    if not ok or not closed then os.remove(tmp); return false, write_err or close_err end
    local old, old_err = read(path)
    if old_err then os.remove(tmp); return false, old_err end
    if old then
        os.remove(backup)
        local moved, reason = os.rename(path, backup)
        if not moved then os.remove(tmp); return false, reason end
    end
    local moved, reason = os.rename(tmp, path)
    if not moved then
        if old then os.rename(backup, path) end
        os.remove(tmp)
        return false, reason
    end
    local loaded = M.reload()
    return loaded, read_error
end

local function refresh()
    if DANMAKU and convert_danmaku_to_ass_events then
        convert_danmaku_to_ass_events(true)
        if ENABLED and HAS_DANMAKU and mp.get_property_bool(HAS_DANMAKU, false) and render then render() end
    end
end

local function notify(text)
    if show_message then show_message(text, 3) else mp.osd_message(text, 3) end
end

function M.add(word)
    if not M.reload() then return false, read_error end
    word = tostring(word or ''):match('^%s*(.-)%s*$')
    if word == '' then return false, '屏蔽词不能为空' end
    if #word > 1024 or word:find('[%z\r\n]') then return false, '请每次输入一个屏蔽词或短语' end
    for _, old in ipairs(state.words) do
        if old:lower() == word:lower() then return false, '该屏蔽词已存在' end
    end
    local words = {}
    for i, old in ipairs(state.words) do words[i] = old end
    words[#words+1] = word
    local ok, err = save({version=1, enabled=state.enabled, words=words, auto=state.auto})
    if ok then refresh() end
    return ok, err
end

function M.remove(word)
    if not M.reload() then return false, read_error end
    local words = {}
    for _, old in ipairs(state.words) do if old ~= word then words[#words+1] = old end end
    local ok, err = save({version=1, enabled=state.enabled, words=words, auto=state.auto})
    if ok then refresh() end
    return ok, err
end

function M.toggle()
    if not M.reload() then return false, read_error end
    local ok, err = save({version=1, enabled=not state.enabled, words=state.words, auto=state.auto})
    if ok then refresh() end
    return ok, err
end

function M.toggle_auto(key)
    if not auto_titles[key] then return false, '未知的自动屏蔽规则' end
    if not M.reload() then return false, read_error end
    local auto = {}
    for _, name in ipairs(auto_keys) do auto[name] = state.auto[name] end
    auto[key] = not auto[key]
    local ok, err = save({version=1, enabled=state.enabled, words=state.words, auto=auto})
    if ok then refresh() end
    return ok, err
end

local function command(action, value)
    local cmd = {'script-message-to', mp.get_script_name(), action}
    if value then cmd[#cmd+1] = value end
    return cmd
end

function M.open(update)
    M.reload()
    local items = {
        {title='返回弹幕设置', icon='arrow_back', value=command('open_add_total_menu')},
        {title='添加屏蔽词…', icon='add', value=command('danmaku-blocklist-input')},
        {title='启用屏蔽', hint=state.enabled and '已开启' or '已关闭', icon=state.enabled and 'toggle_on' or 'toggle_off',
            value=command('danmaku-blocklist-toggle')},
    }
    items[#items].separator = true
    local enabled_count = 0
    for _, key in ipairs(auto_keys) do if state.auto[key] then enabled_count = enabled_count + 1 end end
    items[#items+1] = {title='自动屏蔽规则', hint=enabled_count .. '/3 开启', icon='chevron_right',
        value=command('danmaku-blocklist-auto-open'), separator=true}
    for _, word in ipairs(state.words) do
        items[#items+1] = {title=word, hint='点击删除', icon='delete', value=command('danmaku-blocklist-delete',word), keep_open=true}
    end
    if #state.words == 0 then items[#items+1]={title='尚未添加屏蔽词', selectable=false, italic=true} end
    if uosc_available then
        mp.commandv('script-message-to','uosc',update == true and 'update-menu' or 'open-menu',utils.format_json({
            type='menu_danmaku_blocklist', title='弹幕屏蔽 · ' .. #state.words .. ' 个词', items=items,
            footnote=read_error or '包含屏蔽词即过滤；英文忽略大小写；点击词条删除；自动保存', search_style='on_demand',
        }))
    elseif input_loaded then
        open_menu_select(items)
    end
end

function M.open_auto()
    M.reload()
    local items = {{title='返回屏蔽列表', icon='arrow_back', value=command('danmaku-blocklist-open')}}
    for _, key in ipairs(auto_keys) do
        local enabled = state.auto[key]
        items[#items+1] = {title=auto_titles[key], hint=enabled and '已开启' or '已关闭',
            icon=enabled and 'toggle_on' or 'toggle_off', value=command('danmaku-blocklist-auto-toggle',key)}
    end
    local footnote = read_error or (state.enabled and '点击分别开关并自动保存；关闭规则不影响手动屏蔽词'
        or '总屏蔽已关闭，自动规则暂停；可在屏蔽列表中开启')
    if uosc_available then
        mp.commandv('script-message-to','uosc','open-menu',utils.format_json({type='menu_danmaku_auto_blocklist',
            title='自动屏蔽规则',items=items,footnote=footnote,search_style='disabled'}))
    elseif input_loaded then open_menu_select(items) end
end

local bridge_request, bridge_channel, bridge_active, bridge_text, bridge_display, bridge_layout, shutting_down
local bridge_session, bridge_focus, bridge_command, bridge_action, bridge_seen = 0, 0, 0, 0, 0
local bridge_pending_action
local bridge_pending_control
local bridge_timer
local foreground_api, foreground_granted
do
    local ok, ffi=pcall(require,'ffi')
    if ok then
        pcall(ffi.cdef,'int __stdcall AllowSetForegroundWindow(unsigned long dwProcessId);')
        local loaded, api=pcall(ffi.load,'user32')
        if loaded then foreground_api=api end
    end
end
local function grant_bridge_focus()
    if not bridge_channel or not foreground_api then return false end
    local file=io.open(bridge_channel..'.ready','rb')
    if not file then return false end
    local text=file:read('*a');file:close()
    local data=text and utils.parse_json(text)
    if data and tonumber(data.pid) then
        return foreground_api.AllowSetForegroundWindow(tonumber(data.pid))~=0
    end
    return false
end
local function bridge_cleanup()
    if not bridge_channel then return end
    for _, suffix in ipairs({'.ready','.control','.control.tmp','.event','.event.tmp'}) do
        os.remove(bridge_channel .. suffix)
    end
end
local function flush_bridge_control()
    if not bridge_pending_control or not bridge_channel then return end
    local file=io.open(bridge_channel..'.control.tmp','wb')
    if not file then return end
    local ok=file:write(bridge_pending_control);local closed=file:close()
    if ok and closed then
        os.remove(bridge_channel..'.control')
        local moved=os.rename(bridge_channel..'.control.tmp',bridge_channel..'.control')
        if moved then bridge_pending_control=nil end
    end
end
local function bridge_control()
    if not bridge_channel or not bridge_request then return end
    if bridge_active and (not bridge_layout or bridge_layout.type~='menu_danmaku_blocklist_add') then return end
    if bridge_active then foreground_granted=grant_bridge_focus() or foreground_granted end
    bridge_command=bridge_command+1
    local data={seq=bridge_command,active=not not bridge_active,session=bridge_session,text=bridge_text or '',
        focus=bridge_focus,action_seq=bridge_action,action=bridge_pending_action}
    if bridge_layout then
        for _, key in ipairs({'x','y','width','height','font','font_size'}) do data[key]=bridge_layout[key] end
    end
    bridge_pending_control=utils.format_json(data)
    flush_bridge_control()
end
local function warm_bridge()
    if shutting_down or bridge_request then return end
    bridge_cleanup()
    bridge_channel=utils.join_path(os.getenv('TEMP') or os.getenv('TMP') or mp.get_script_directory(),
        string.format('.mpv-uosc-ime-%s-%.0f',utils.getpid(),mp.get_time()*1000000))
    bridge_seen=0
    foreground_granted=false
    local args={utils.join_path(mp.get_script_directory(),'UoscInputBridge.exe'),
        '-OwnerProcessId',tostring(utils.getpid()),'-Channel',bridge_channel}
    bridge_request=mp.command_native_async({name='subprocess',args=args,playback_only=false,capture_stdout=true,capture_stderr=true},
        function(success,result,reason)
            bridge_request=nil
            bridge_cleanup()
            if not shutting_down and bridge_active then
                notify('中文输入桥接已退出：'..tostring(reason or (result and result.stderr) or '未知错误'))
                bridge_active=false
            end
        end)
end
local function close_bridge()
    bridge_active=false
    bridge_control()
end
local function bridge_submit(data)
    if not bridge_active or data.session~=bridge_session then return end
    if (tonumber(data.composition_start) or -1)>=0 then
        notify('请先完成中文输入法选词');return
    end
    local ok, err=M.add(data.text or '')
    if ok then close_bridge();M.open() else M.input(data.text,err) end
end
local function bridge_poll()
    flush_bridge_control()
    if not bridge_channel or not bridge_active then return end
    if not foreground_granted and grant_bridge_focus() then
        foreground_granted=true;bridge_focus=bridge_focus+1;bridge_control()
    end
    local file=io.open(bridge_channel..'.event','rb')
    if not file then return end
    local text=file:read('*a');file:close()
    local parsed=text and utils.parse_json(text)
    if not parsed or type(parsed.events)~='table' then return end
    for _, data in ipairs(parsed.events) do
        local seq=tonumber(data.seq) or 0
        if seq>bridge_seen then
            bridge_seen=seq
            if data.session==bridge_session and bridge_active then
                if data.kind=='text' then
                    bridge_text=data.text or ''
                    bridge_display=data.display or bridge_text
                    data.type='menu_danmaku_blocklist_add'
                    mp.commandv('script-message-to','uosc','native-input-update',utils.format_json(data))
                elseif data.kind=='submit' then bridge_submit(data)
                elseif data.kind=='cancel' then close_bridge();M.open()
                elseif data.kind=='focus' then bridge_focus=bridge_focus+1;bridge_control()
                elseif data.kind=='key' and (data.key=='UP' or data.key=='DOWN' or data.key=='TAB' or data.key=='ENTER') then
                    mp.commandv('keypress',data.key)
                end
            end
        end
    end
end
mp.observe_property('user-data/uosc/native-input','native',function(_,layout)
    bridge_layout=layout
    if bridge_active and layout then
        if type(layout.query)=='string' and layout.query~=bridge_display then
            bridge_text=layout.query;bridge_display=layout.query
        end
        bridge_control()
    end
end)
mp.register_script_message('danmaku-blocklist-native-focus',function()
    if bridge_active then bridge_focus=bridge_focus+1;bridge_control() end
end)
mp.register_script_message('danmaku-blocklist-native-edit',function(query)
    if bridge_active then
        bridge_text=query or '';bridge_control()
    end
end)
mp.register_script_message('danmaku-blocklist-native-submit',function()
    if bridge_active then bridge_action=bridge_action+1;bridge_pending_action='submit';bridge_control() end
end)
mp.register_script_message('danmaku-blocklist-native-cancel',function()
    if bridge_active then close_bridge();M.open() end
end)
mp.register_script_message('danmaku-blocklist-native-close',function(session)
    if tonumber(session)==bridge_session then close_bridge() end
end)
mp.register_event('shutdown',function()
    shutting_down=true
    if bridge_timer then bridge_timer:kill() end
    if bridge_request then mp.abort_async_command(bridge_request);bridge_request=nil end
    bridge_cleanup()
end)
if mp.get_property_native('platform')=='windows' or os.getenv('windir') then
    bridge_timer=mp.add_periodic_timer(0.025,bridge_poll)
    mp.add_timeout(0.1,warm_bridge)
end

function M.input(text, error)
    if uosc_available then
        local windows=mp.get_property_native('platform')=='windows' or os.getenv('windir')
        if windows then
            warm_bridge()
            bridge_session=bridge_session+1
            bridge_active=true;bridge_text=text or '';bridge_display=bridge_text;bridge_focus=bridge_focus+1
            bridge_pending_action=nil
        end
        mp.commandv('script-message-to','uosc','open-menu',utils.format_json({
            type='menu_danmaku_blocklist_add',title=error or '输入屏蔽词或短语',
            native_input=not not windows,native_input_focus=command('danmaku-blocklist-native-focus'),
            search_style='palette',search_debounce='submit',search_suggestion=text or '',
            on_search=command(windows and 'danmaku-blocklist-native-submit' or 'danmaku-blocklist-add'),
            on_close=windows and command('danmaku-blocklist-native-close',tostring(bridge_session)) or nil,
            footnote='支持中文输入法与 Ctrl+V 粘贴；回车添加，Esc 返回；自动保存',
            items={
                {title='添加屏蔽词',icon='add',hint='Enter',value=command(windows and 'danmaku-blocklist-native-submit' or 'danmaku-blocklist-add',text or ''),keep_open=true},
                {title='取消并返回',icon='arrow_back',hint='Esc',value=command(windows and 'danmaku-blocklist-native-cancel' or 'danmaku-blocklist-open')},
            },
        }))
        if windows then bridge_control() end
    elseif input_loaded then
        input.get({prompt='屏蔽词：',default_text=text or '',submit=function(word)
            input.terminate();local ok,err=M.add(word);if not ok then notify(err) end;M.open()
        end})
    end
end

mp.register_script_message('danmaku-blocklist-auto-open',M.open_auto)
mp.register_script_message('danmaku-blocklist-auto-toggle',function(key)
    local ok, err = M.toggle_auto(key)
    if not ok then notify(err or '自动屏蔽设置保存失败') end
    M.open_auto()
end)
mp.register_script_message('danmaku-blocklist-open',M.open)
mp.register_script_message('danmaku-blocklist-input',M.input)
mp.register_script_message('danmaku-blocklist-add',function(word)
    local ok, err=M.add(word)
    if ok then M.open() else M.input(word,err) end
end)
mp.register_script_message('danmaku-blocklist-delete',function(word)
    local ok, err=M.remove(word)
    if not ok then notify(err or '屏蔽词保存失败') end
    M.open(true)
end)
mp.register_script_message('danmaku-blocklist-toggle',function()
    local ok, err=M.toggle()
    if not ok then notify(err or '屏蔽词保存失败') end
    M.open()
end)

M.reload()
return M
