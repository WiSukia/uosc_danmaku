"""Portable behavioral checks; requires lupa (Lua 5.1 backend)."""
from pathlib import Path
import json
import tempfile
from lupa.lua51 import LuaRuntime

repo = Path(__file__).resolve().parents[1]

def player(path):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.path = path.as_posix()
    lua.execute("package.path = " + json.dumps(repo.as_posix()+'/?.lua;') + " .. package.path")
    def decode(text, *_):
        try: return lua.table_from(json.loads(text), recursive=True)
        except (ValueError, TypeError): return None
    def encode(value):
        return json.dumps({'version':value.version,'enabled':value.enabled,
            'words':[value.words[i] for i in range(1,len(value.words)+1)],
            'auto':{key:bool(value.auto[key]) for key in ('date','people','group')}},ensure_ascii=False)
    g.decode, g.encode = decode, encode
    lua.execute('''
        mp={command_native=function() return path end,
            get_script_name=function() return 'uosc_danmaku' end,
            get_property_native=function() return 'linux' end,
            observe_property=function() end, register_event=function() end,
            register_script_message=function() end, commandv=function() end,
            add_periodic_timer=function() return {kill=function() end} end,
            add_timeout=function() end, osd_message=function() end,
            msg={error=function(m) error(m) end, info=function() end}}
        package.preload['mp']=function() return mp end
        package.preload['mp.msg']=function() return mp.msg end
        package.preload['mp.utils']=function() return {
            parse_json=decode,format_json=encode,getpid=function() return 1 end,
            join_path=function(a,b) return a..'/'..b end} end
        package.preload['mp.options']=function() return {read_options=function() end} end
    ''')
    return lua

with tempfile.TemporaryDirectory() as directory:
    config=Path(directory)/'uosc_danmaku.conf'
    lua=player(config)
    lua.execute((repo/'modules/options.lua').read_text(encoding='utf-8'))
    lua.execute("options.fontsize=36; save_danmaku_style_option('fontsize')")
    assert config.read_text(encoding='utf-8') == 'fontsize=36\n'
    config.write_bytes(b'# preserve\r\napi_server=https://example.test\r\nfontsize=35 # inline\r\nproxy=keep\r\n')
    lua.execute("options.fontsize=40; save_danmaku_style_option('fontsize')")
    assert config.read_bytes() == b'# preserve\r\napi_server=https://example.test\r\nfontsize=40 # inline\r\nproxy=keep\r\n'
    lua.execute("assert(normalize_danmaku_fps('120')=='120'); assert(normalize_danmaku_fps('60000/1001')); assert(not normalize_danmaku_fps('1/0')); assert(not normalize_danmaku_font('bad\\nfont'))")
    config_before=config.read_bytes()
    lua.execute("options.fontname='bad\\nfont'; save_danmaku_style_option('fontname')")
    assert config.read_bytes()==config_before
    # Reload the Lua options reader against the saved file.
    fresh=player(config)
    fresh.execute('''package.preload['mp.options']=function() return {read_options=function(o)
        local f=assert(io.open(path,'rb')); local s=f:read('*a'); f:close()
        o.fontsize=tonumber(s:match('fontsize=(%d+)'))
    end} end''')
    fresh.execute((repo/'modules/options.lua').read_text(encoding='utf-8'))
    assert fresh.globals().options.fontsize==40

    store=Path(directory)/'words.json'
    lua=player(store)
    lua.globals().words=lua.execute((repo/'modules/blocklist.lua').read_text(encoding='utf-8'))
    lua.execute("assert(words.add('剧透')); assert(words.add('Spoiler')); assert(not words.add('spoiler')); assert(words.matches('这里有剧透')); assert(words.matches('SPOILER ALERT')); assert(not words.matches('正常弹幕')); assert(words.toggle()); assert(not words.matches('剧透')); assert(words.toggle()); assert(words.remove('剧透')); assert(not words.matches('剧透'))")
    assert json.loads(store.read_text(encoding='utf-8'))['words']==['Spoiler']
    fresh=player(store)
    fresh.globals().words=fresh.execute((repo/'modules/blocklist.lua').read_text(encoding='utf-8'))
    fresh.execute("assert(words.matches('spoiler')); assert(words.add('a[b')); assert(words.matches('xxa[bxx')); assert(not words.matches('axb'))")
    store.write_text('{invalid',encoding='utf-8')
    before=store.read_bytes()
    fresh.execute("assert(not words.add('do not overwrite'))")
    assert store.read_bytes()==before

# Exercise the actual fold function with utility implementations from the repo.
lua=player(Path('unused'))
lua.execute((repo/'modules/utils.lua').read_text(encoding='utf-8'))
lua.execute("options={merge_window=15,scrolltime=15,fixtime=5}; function ch_convert_cached(s) return s end; function decode_html_entities(s) return s end")
parse=(repo/'modules/parse.lua').read_text(encoding='utf-8')
start=parse.index('local ignored_fold_chars')
end=parse.index('-- 限制每屏弹幕条数',start)
lua.globals().fold=lua.execute(parse[start:end]+'\nreturn fold_danmaku_time_window')
lua.execute('''
    local a={{time=0,type=1,text='Test!',color=1},{time=1,type=1,text='test',color=2},
        {time=2,type=1,text='test',color=2},{time=14,type=1,text='TEST',color=3},
        {time=15,type=1,text='test',color=4},{time=29,type=1,text='test',color=4},
        {time=30,type=1,text='test',color=4}}
    local b=fold(a)
    assert(#b==3 and b[1].merge_count==4 and b[1].text=='test' and b[1].time==0)
    assert(b[2].merge_count==2 and b[3].merge_count==1)
    assert(a[1].text=='Test!' and a[1].merge_count==nil)
    local c=fold({{time=0,type=1,text='1.2'},{time=1,type=1,text='12'},
        {time=2,type=1,text='签到！'},{time=3,type=1,text='签到'}})
    assert(#c==3 and c[3].merge_count==2)
    local d=fold({{time=0,type=4,text='固定'},{time=4,type=4,text='固定！'},{time=5,type=4,text='固定'}})
    assert(#d==2 and d[1].merge_count==2)
''')
print('PASS style creation/preservation/reload; literal blocklist/persistence/corrupt-file protection; fixed folding windows/counts/winner/digit separators.')
