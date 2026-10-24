"""Transport and search lifecycle checks using a deterministic Lua 5.1 player."""
import json
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def player():
    lua = LuaRuntime(unpack_returned_tuples=True)
    def decode(value):
        try:
            return lua.table_from(json.loads(value), recursive=True)
        except (TypeError, ValueError):
            return None
    lua.globals().decode = decode
    lua.execute(r'''
        now=0; requests={}; timers={}; events={}; messages={}; aborted={}; calls={}
        mp={get_time=function() return now end,
            get_script_name=function() return 'uosc_danmaku' end,
            get_property=function() return 'fixture' end,
            register_script_message=function(k,f) messages[k]=f end,
            command_native=function() error('synchronous request forbidden') end,
            commandv=function() end,
            register_event=function(k,f)
                events[k]=events[k] or {}; table.insert(events[k],f)
            end,
            add_timeout=function(delay,f)
                local t={delay=delay,callback=f,alive=true,kill=function(self) self.alive=false end}
                table.insert(timers,t); return t
            end,
            command_native_async=function(spec,cb)
                table.insert(requests,{args=spec.args,cb=cb,spec=spec}); return #requests
            end,
            abort_async_command=function(id) aborted[id]=true end}
        logs={}
        local function log(s) table.insert(logs,s) end
        package.preload['mp']=function() return mp end
        package.preload['mp.msg']=function() return {verbose=log,info=log,warn=log,error=log} end
        package.preload['mp.utils']=function() return {parse_json=decode,
            format_json=function() return '{}' end} end
        function reply(id,exit,status,body,success)
            local out=(body or '{}')..'\n__UOSC_DANMAKU_HTTP__:'..string.format('%03d',status or 0)
            requests[id].cb(success~=false,{status=exit,stdout=out,stderr='secret body'},nil)
        end
        function tick()
            for _,t in ipairs(timers) do
                if t.alive then t.alive=false; now=now+t.delay; t.callback(); return end
            end
            error('no retry timer')
        end
        function event(k) for _,f in ipairs(events[k] or {}) do f() end end
        function request(url,method)
            return H.request({'curl','-L','-X',method or 'GET',url},function(err,body)
                table.insert(calls,{err=err,body=body})
            end)
        end
        primary='https://danmaku-api.152468.xyz'
        backup='https://danmaku-us.152468.xyz'
        url=primary..'/api/v2/search/anime?keyword=private'
        function host(id) return requests[id].args[#requests[id].args]:match('^https://[^/]+') end
        function has(id,flag,value)
            for i,v in ipairs(requests[id].args) do
                if v==flag and (value==nil or requests[id].args[i+1]==value) then return true end
            end
            return false
        end
    ''')
    lua.globals().H = lua.execute((ROOT / 'modules/http.lua').read_text('utf-8'))
    lua.execute("package.loaded['modules/http']=H")
    return lua


cases = [
    ('success and timeouts', '''request(url); assert(has(1,'--connect-timeout','5') and has(1,'--max-time','12'))
        reply(1,0,200,'{"ok":true}'); assert(#calls==1 and calls[1].body=='{"ok":true}' and not calls[1].err)
        assert(not async_running)'''),
    ('reset retry', '''request(url); reply(1,35); assert(#calls==0 and async_running)
        tick(); reply(2,0,200); assert(#calls==1 and not calls[1].err and host(2)==primary)'''),
    ('failover and preference expiry', '''request(url); reply(1,35); tick(); reply(2,35); tick()
        assert(host(3)==backup); reply(3,0,200); request(url); assert(host(4)==backup)
        reply(4,0,200); now=now+61; request(url); assert(host(5)==primary)'''),
    ('four attempt bound', '''request(url)
        for i=1,4 do reply(i,35); if i<4 then tick() end end
        assert(#requests==4 and #calls==1 and calls[1].err and not async_running)
        assert(not table.concat(logs):find('private') and not table.concat(logs):find('secret body'))'''),
    ('cancel retry timer', '''cancel=request(url); reply(1,35); cancel()
        assert(not timers[1].alive and not async_running and #calls==0 and #requests==1)'''),
    ('cancel running process and late completion', '''cancel=request(url); cancel(); reply(1,0,200)
        assert(aborted[1] and #calls==0 and not async_running)'''),
    ('end-file cancels pending requests', '''request(url); event('end-file'); reply(1,35)
        assert(aborted[1] and #timers==0 and #calls==0)'''),
    ('start-file cancels retry', '''request(url); reply(1,35); event('start-file')
        assert(not timers[1].alive and not async_running)'''),
    ('shutdown cancels requests', '''request(url); event('shutdown'); assert(aborted[1])'''),
    ('custom origins never fail over', '''request('https://example.test/token/api?key=private')
        reply(1,35); tick(); reply(2,35); assert(#requests==2 and #calls==1)
        assert(not table.concat(logs):find('token') and not table.concat(logs):find('private'))'''),
    ('429 does not retry', '''request(url); reply(1,0,429); assert(#requests==1 and #timers==0 and calls[1].err)'''),
    ('403 does not retry', '''request(url); reply(1,0,403); assert(#requests==1 and #timers==0 and calls[1].err)'''),
    ('certificate errors do not retry', '''request(url); reply(1,60); assert(#timers==0 and #calls==1)'''),
    ('server failure recovers', '''request(url); reply(1,0,503); tick(); reply(2,0,200); assert(not calls[1].err)'''),
    ('bad JSON recovers', '''request(url); reply(1,0,200,'<html>error</html>'); tick()
        reply(2,0,200); assert(#calls==1 and not calls[1].err)'''),
    ('empty valid response is preserved', '''request(url); reply(1,0,200,'{"success":false}')
        assert(#calls==1 and #timers==0 and not calls[1].err)'''),
    ('POST body is preserved on failover', '''H.request({'curl','-X','POST','-H','Content-Type: application/json',
        '-d','{"fileHash":"fixture"}',primary..'/api/v2/match'},function() end)
        reply(1,35); tick(); reply(2,35); tick()
        assert(has(3,'-X','POST') and has(3,'-d','{"fileHash":"fixture"}') and host(3)==backup)'''),
    ('parallel requests keep busy state', '''request(url); request(url); reply(1,0,200)
        assert(async_running); reply(2,0,200); assert(not async_running and #calls==2)'''),
    ('subprocess command failure cannot hang', '''request(url); requests[1].cb(false,nil,'failed')
        assert(#calls==1 and calls[1].err and not async_running)'''),
    ('reset reported with failed command', '''request(url); reply(1,35,0,'',false)
        tick(); reply(2,0,200); assert(not calls[1].err)'''),
]

for name, code in cases:
    player().execute(code)
    print('PASS', name)

# Exercise the production argument factory and dispatcher, rather than only
# directly calling the transport. No headers or credentials are sent anywhere.
lua = player()
lua.execute((ROOT / 'modules/utils.lua').read_text('utf-8'))
lua.execute((ROOT / 'apis/dandanplay.lua').read_text('utf-8'))
lua.execute('''options={user_agent='fixture',proxy=''}
    local args=make_danmaku_request_args('GET',url)
    assert(args.danmaku_json_request)
    call_cmd_async(args,function(err,body) assert(not err); routed=body end)
    reply(1,0,200); assert(routed=='{}' and requests[1].args.danmaku_json_request==nil)''')
print('PASS production request factory and dispatcher')

# Exhausted transport errors must not create another filename lookup, while a
# successful hash lookup returning no match still uses the filename fallback.
def matching_player():
    lua = player()
    lua.execute((ROOT / 'modules/utils.lua').read_text('utf-8'))
    lua.execute((ROOT / 'apis/dandanplay.lua').read_text('utf-8'))
    lua.execute('''options={user_agent='fixture',proxy='',api_server=primary,excluded_path='[]'}
        MD5={sum=function() end}; PLATFORM='windows'
        require('mp.utils').file_info=function() return nil end
        function parse_title() return 'fixture',nil,1 end
        function show_message() end
        function get_parent_directory() return 'fixture' end
        function contains_any() return false end
    ''')
    return lua

matching_player().execute('''get_danmaku_with_hash('fixture','fixture.mkv')
    for i=1,4 do reply(i,35); if i<4 then tick() end end
    assert(#requests==4 and not async_running)''')
matching_player().execute('''get_danmaku_with_hash('fixture','fixture.mkv')
    reply(1,0,200,'{"isMatched":false}'); assert(#requests==2)
    assert(requests[2].args[#requests[2].args]:find('/search/anime'))''')
print('PASS matching stops after transport exhaustion, retains normal filename fallback')

# Search results must be asynchronous, distinguish errors from no results,
# and ignore callbacks/timers from a previous search or closed menu.
lua.execute((ROOT / 'modules/menu.lua').read_text('utf-8'))
lua.execute('''uosc_available=true; menu_updates={}; options.api_server=primary
    function url_encode(x) return x end
    function update_menu_uosc(kind,title,items)
        table.insert(menu_updates,{kind=kind,items=items}); return '{}'
    end
    function show_message() end
    get_animes('first'); local first=#requests
    get_animes('second'); local second=#requests
    assert(aborted[first] and #menu_updates==2)
    reply(first,0,200,'{"animes":[{"animeTitle":"stale"}]}'); assert(#menu_updates==2)
    reply(second,0,200,'{"animes":[{"animeTitle":"current"}]}')
    assert(menu_updates[3].items[1].title=='current')
    get_episodes('current',1); local episode=#requests
    reply(episode,0,403); assert(menu_updates[#menu_updates].items=='获取数据失败')
    get_animes('third'); local third=#requests
    event('end-file'); reply(third,0,200,'{"animes":[]}')
    assert(menu_updates[#menu_updates].items=='加载数据中...')
''')
print('PASS asynchronous menu search, stale results, errors and unload')

# Compile all shipped Lua, including unchanged feature code.
lua = LuaRuntime()
compile_lua = lua.eval('function(s) return assert(loadstring(s)) end')
files = list(ROOT.glob('modules/*.lua')) + list(ROOT.glob('apis/*.lua')) + [ROOT / 'main.lua']
for path in files:
    compile_lua(path.read_text('utf-8-sig'))
print('PASS Lua 5.1 syntax:', len(files), 'files')
