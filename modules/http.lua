-- Bounded transport for JSON API requests. Only the author's two equivalent
-- DanDanPlay relays may exchange requests; unrelated servers keep their origin.
local mp = require('mp')
local msg = require('mp.msg')
local utils = require('mp.utils')
local M = {}
local CONNECT_TIMEOUT, REQUEST_TIMEOUT = 5, 12
local RETRIES, RETRY_DELAY = 1, 1
local peers = {
    ['https://danmaku-api.152468.xyz'] = 'https://danmaku-us.152468.xyz',
    ['https://danmaku-us.152468.xyz'] = 'https://danmaku-api.152468.xyz',
}
local transient = {[5]=true, [6]=true, [7]=true, [18]=true, [28]=true,
    [35]=true, [52]=true, [55]=true, [56]=true, [92]=true}
local active, preferred = {}, {}
local marker = '\n__UOSC_DANMAKU_HTTP__:'

local function safe_endpoint(url)
    local origin, path = url:match('^(https?://[^/]+)(.*)$')
    if not origin then return '<invalid URL>' end
    -- Do not log queries, filenames, hashes, credentials or custom API tokens.
    origin = origin:gsub('//[^/@]+@', '//<redacted>@')
    if peers[origin] then return origin .. (path:match('^[^?]*') or '') end
    return origin .. '/<redacted>'
end

local function update_running()
    async_running = next(active) ~= nil
end

function M.request(args, callback)
    local original = args[#args]
    local origin, suffix = original:match('^(https?://[^/]+)(/.*)$')
    local first = origin
    if preferred[origin] and preferred[origin].until_time > mp.get_time() then
        first = preferred[origin].origin
    end
    local servers = {first or ''}
    if peers[first] then servers[2] = peers[first] end
    local state = {done=false, server=1, attempt=0}
    active[state] = true
    update_running()

    local function cancel()
        if state.done then return end
        state.done = true
        active[state] = nil
        if state.timer then state.timer:kill(); state.timer = nil end
        if state.process then mp.abort_async_command(state.process); state.process = nil end
        update_running()
    end
    state.cancel = cancel

    local function finish(err, body)
        if state.done then return end
        state.done = true
        active[state] = nil
        update_running()
        callback(err, body)
        -- Callers may start another request from inside their callback.
        update_running()
    end

    local launch
    local function later()
        state.timer = mp.add_timeout(RETRY_DELAY, function()
            state.timer = nil
            if not state.done then launch() end
        end)
    end
    launch = function()
        if state.done then return end
        state.attempt = state.attempt + 1
        local server = servers[state.server]
        local url = origin and server .. suffix or original
        local command = {}
        for i, value in ipairs(args) do command[i] = value end
        command[#command] = url
        -- Marker is removed before delivering the original JSON to the caller.
        table.insert(command, 2, '--silent')
        table.insert(command, 3, '--show-error')
        table.insert(command, 4, '--connect-timeout')
        table.insert(command, 5, tostring(CONNECT_TIMEOUT))
        table.insert(command, 6, '--max-time')
        table.insert(command, 7, tostring(REQUEST_TIMEOUT))
        table.insert(command, 8, '--write-out')
        table.insert(command, 9, marker .. '%{http_code}')
        msg.verbose(('API request %s attempt %d/%d'):format(
            safe_endpoint(url), state.attempt, RETRIES + 1))
        state.process = mp.command_native_async({name='subprocess',
            capture_stderr=true, capture_stdout=true, playback_only=false,
            args=command}, function(success, result, error_text)
            if state.done then return end
            state.process = nil
            local exit = result and result.status
            local stdout = result and result.stdout or ''
            local body, status = stdout:match('^(.*)' .. marker .. '(%d%d%d)$')
            status = tonumber(status)
            local valid_json = body and type(utils.parse_json(body)) == 'table'
            if success and exit == 0 and status and status >= 200 and status < 300 and valid_json then
                if peers[origin] then
                    preferred[origin] = {origin=server, until_time=mp.get_time()+60}
                end
                if state.server > 1 then msg.info('弹幕 API 已切换至 ' .. safe_endpoint(url)) end
                finish(nil, body)
                return
            end
            local reason = ('curl=%s HTTP=%s'):format(tostring(exit or 'unknown'), tostring(status or 'unknown'))
            if exit == 0 and status and status >= 200 and status < 300 and not valid_json then
                reason = reason .. ' invalid JSON'
            end
            -- Keep diagnostics useful without printing response bodies, request
            -- parameters, proxy credentials or curl's potentially sensitive text.
            local detail = safe_endpoint(url) .. ' ' .. reason
            local retryable = result and (transient[exit] or
                (success and exit == 0 and status and status >= 500 and status <= 599) or
                (success and exit == 0 and status and status >= 200 and status < 300 and not valid_json))
            -- 429 and other client errors return immediately; don't amplify
            -- rate limits or bypass them by hopping to another relay.
            if status and status >= 400 and status < 500 then retryable = false end
            if retryable and state.attempt <= RETRIES then
                msg.warn(detail .. '; 1 秒后重试')
                later()
            elseif retryable and state.server < #servers then
                msg.warn(detail .. '; 切换至备用接口')
                state.server = state.server + 1
                state.attempt = 0
                later()
            else
                msg.error('弹幕 API 请求失败: ' .. detail)
                finish('API request failed: ' .. detail, '')
            end
        end)
    end
    launch()
    return cancel
end

local function cancel_all()
    local pending = {}
    for state in pairs(active) do pending[#pending+1] = state end
    for _, state in ipairs(pending) do state.cancel() end
end
mp.register_event('start-file', cancel_all)
mp.register_event('end-file', cancel_all)
mp.register_event('shutdown', cancel_all)
return M
