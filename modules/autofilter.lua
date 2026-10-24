-- Conservative, local rules. No network requests and no changes to source comments.
local M = {}

local fullwidth = {'０','１','２','３','４','５','６','７','８','９'}
local punctuation = {['：']=':', ['／']='/', ['－']='-', ['．']='.', ['。']='.',
    ['！']='!', ['，']=',', ['；']=';', ['～']='~', ['（']='(', ['）']=')'}
local function normalize(text)
    text = tostring(text or ''):lower()
    for i, digit in ipairs(fullwidth) do text = text:gsub(digit, tostring(i - 1)) end
    for from, to in pairs(punctuation) do text = text:gsub(from, to) end
    for _, space in ipairs({'　',' ','​'}) do text = text:gsub(space, '') end
    return text:gsub('%s+', '')
end
local function trim(text)
    return (text:gsub('^[!.,:;~_%-]+', ''):gsub('[!.,:;~_%-]+$', ''))
end
local function set(values)
    local result = {}
    for _, value in ipairs(values) do result[value] = true end
    return result
end
local date_prefixes = set({'','今天','今天是','现在','现在是','打卡','签到','簽到','报到','報到','考古','前来考古','留念'})
local date_suffixes = set({'','打卡','签到','簽到','报到','報到','路过','到此一游','前来考古','考古','留念','重温','来过','入坑'})
local function valid_date(year, month, day)
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year or year < 1900 or year > 2199 or not month or month < 1 or month > 12 or not day then return false end
    local days = {31,28,31,30,31,30,31,31,30,31,30,31}
    if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then days[2] = 29 end
    return day >= 1 and day <= days[month]
end
local function date(text)
    local first = text:find('%d')
    if not first or not date_prefixes[trim(text:sub(1, first - 1))] then return false end
    local body = text:sub(first)
    local y, sep, m, sep2, d, tail = body:match('^(%d%d%d%d)([./%-])(%d%d?)([./%-])(%d%d?)(.*)$')
    if y then return sep == sep2 and valid_date(y,m,d) and date_suffixes[trim(tail)] == true end
    y,m,d,tail = body:match('^(%d%d%d%d)年(%d%d?)月(%d%d?)日(.*)$')
    if y then return valid_date(y,m,d) and date_suffixes[trim(tail)] == true end
    y,m,d = body:match('^(%d%d%d%d)年(%d%d?)月(%d%d?)$')
    if y then return valid_date(y,m,d) end
    m,d,tail = body:match('^(%d%d?)月(%d%d?)日(.*)$')
    return m ~= nil and valid_date(2024,m,d) and date_suffixes[trim(tail)] == true
end

local count_prefixes = set({'','在线','当前在线','同时在线','在看','正在看','观看人数','在线人数','总人数','人数','当前人数'})
local count_suffixes = set({'人','位','人在看','人在线','人观看','人正在看','人观看中','人在观看'})
local function people(text)
    local prefix, amount, suffix = text:match('^(.-)(%d[%d%.,]*)(.*)$')
    if not prefix or not count_prefixes[trim(prefix)] then return false end
    prefix, suffix = trim(prefix), trim(suffix)
    for _, unit in ipairs({'万','千','w','k'}) do
        if suffix:sub(1,#unit) == unit then suffix = suffix:sub(#unit + 1); break end
    end
    amount = amount:gsub(',', '')
    if not amount:match('^%d+$') and not amount:match('^%d+%.%d+$') then return false end
    return count_suffixes[suffix] == true or (prefix ~= '' and suffix == '')
end

local group_contexts = {'qq群','q群','群号','群號','加群','进群','進群','交流群','聊天群','动漫群','粉丝群','同好群','群聊'}
local function group(text)
    local context = false
    for _, term in ipairs(group_contexts) do
        if text:find(term,1,true) then context = true; break end
    end
    if not context then return false end
    -- Recognize ordinary spacing and common separators, never plain long numbers alone.
    local compact = text:gsub('[%s%-%._,]', '')
    for digits in compact:gmatch('%d+') do
        if #digits >= 5 and #digits <= 12 then return true end
    end
    for _, phrase in ipairs({'欢迎加群','欢迎加入','加入交流群','加入聊天群','加群交流','进群交流','加群一起','进群一起','交流群招募'}) do
        if text:find(phrase,1,true) then return true end
    end
    return false
end

function M.matches(text, enabled)
    if not enabled or not (enabled.date or enabled.people or enabled.group) then return false end
    text = normalize(text)
    if enabled.date and date(text) then return true, 'date' end
    if enabled.people and people(text) then return true, 'people' end
    if enabled.group and group(text) then return true, 'group' end
    return false
end
return M
