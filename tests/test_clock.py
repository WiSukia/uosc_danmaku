from pathlib import Path
import sys

from lupa.lua51 import LuaRuntime

stage = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
now=0; props={['time-pos']=5, speed=1, ['video-speed-correction']=1,
    ['play-direction']='forward', ['display-fps']=144, ['estimated-vf-fps']=24, ['video-sync']='audio'}
observations={}; events={}; hooks={}; updates=0; filters={
    {name='scale',label='unrelated',params={}}, {name='fps',label='danmaku',params={fps='120'}}}
mp={get_time=function() return now end,
    get_script_name=function() return 'uosc_danmaku' end,
    command_native=function() return 'unused' end,
    set_property=function(n,v) props[n]=v; return true end,
    get_property_number=function(n,d) if props[n]~=nil then return props[n] end return d end,
    get_property_bool=function(n,d) if props[n]~=nil then return props[n] end return d end,
    get_property=function(n) return props[n] end,
    get_property_native=function() return filters end,
    set_property_bool=function() end, set_property_native=function() end,
    observe_property=function(n,_,fn) observations[n]=fn end,
    unobserve_property=function(fn) if observations['time-pos']==fn then observations['time-pos']=nil end end,
    register_event=function(n,fn) events[n]=fn end, add_hook=function(n,_,fn) hooks[n]=fn end,
    add_periodic_timer=function(t,fn)
        timer={timeout=t,callback=fn,active=true,
            kill=function(self) self.active=false end, resume=function(self) self.active=true end}
        return timer
    end,
    create_osd_overlay=function()
        overlay={update=function(self) updates=updates+1; rendered=self.data end,
            remove=function() rendered='' end}; return overlay
    end,
    commandv=function(...)
        local a={...}
        if a[1]=='vf' then
            assert(a[2]=='remove' and a[3]=='@danmaku')
            for i=#filters,1,-1 do if filters[i].label=='danmaku' then table.remove(filters,i) end end
        end
    end,
    osd_message=function() end,
    msg={error=function(m) error(m) end}}
package.preload['mp.msg']=function() return mp.msg end
package.preload['mp.utils']=function() return {join_path=function() return 'unused' end} end
package.preload['mp.options']=function() return {read_options=function() end} end
function get_danmaku_visibility() return visible end
function set_danmaku_visibility(v) visible=v end
function binary_search() return 1 end
function file_exists() return false end
function show_loaded() end
function tick(dt) now=now+dt; if timer.active then timer.callback() end end
function observe(n,v) props[n]=v; observations[n](n,v) end
''')
lua.execute((stage/'modules/options.lua').read_text(encoding='utf-8'))
lua.execute((stage/'modules/render.lua').read_text(encoding='utf-8'))
lua.execute(r'''
ENABLED=true; PID=1; HAS_DANMAKU='fixture'; DELAY_PROPERTY='fixture-delay'; DANMAKU={sources={}}
options.fps='120'; COMMENTS={{start_time=0,end_time=30,move={1920,50,-1920,50},text='test',style='SP'}}
observe('osd-width',1920); observe('osd-height',1080)
observe('pause',false); observe('core-idle',false)
show_danmaku_func()
assert(props['video-sync']=='display-resample')
assert(timer.active and math.abs(timer.timeout-1/120)<1e-9)
assert(#filters==1 and filters[1].label=='unrelated')
-- Advance inside a single 24 FPS frame, without changing time-pos.
local first=rendered; local count=updates
tick(1/120); assert(rendered~=first and updates==count+1 and props['time-pos']==5)
local function x() return tonumber(rendered:match('\pos%(([-%d%.]+),')) end
local before=x(); tick(1/120); assert(math.abs(before-x()-128/120)<0.15)
observe('speed',2); before=x(); tick(1/120); assert(math.abs(before-x()-256/120)<0.15)
observe('pause',true); first=rendered; count=updates
tick(1); assert(not timer.active and rendered==first and updates==count)
-- Paused frame stepping redraws exactly at the new video position.
observe('time-pos',6); assert(rendered~=first and not timer.active)
observe('pause',false); assert(timer.active)
observe('paused-for-cache',true); first=rendered; tick(1); assert(rendered==first and not timer.active)
observe('paused-for-cache',false); assert(timer.active)
events.seek({}); first=rendered; tick(1); assert(not timer.active and rendered==first)
props['time-pos']=15; observe('seeking',false); events['playback-restart']({})
assert(timer.active and math.abs(x())<0.1)
observe('speed',1); observe('play-direction','backward'); before=x(); tick(1/120); assert(x()>before)
options.fps='60/1.001'; refresh_danmaku_fps(); assert(math.abs(timer.timeout-1.001/60)<1e-9)
options.fps='1000'; refresh_danmaku_fps(); assert(math.abs(timer.timeout-1/144)<1e-9)
observe('display-fps',60); assert(math.abs(timer.timeout-1/60)<1e-9)
hide_danmaku_func(); tick(1); assert(not timer.active and rendered=='' and observations['time-pos']==nil)
assert(props['video-sync']=='audio')
observe('pause',true); observe('pause',false); assert(not timer.active and rendered=='')
show_danmaku_func(); assert(timer.active); hooks.on_unload()
assert(not timer.active and rendered=='' and COMMENTS==nil)
assert(props['video-sync']=='audio')
''')
# Compile every modified module with the actual Lua 5.1 parser.
for name in ('render.lua', 'options.lua', 'menu.lua'):
    lua.eval('function(s) return assert(loadstring(s)) end')((stage/'modules'/name).read_text(encoding='utf-8'))
menu = (stage/'modules/menu.lua').read_text(encoding='utf-8')
assert 'vf_fps' not in menu and '弹幕帧率增强' not in menu
print('PASS Lua 5.1 independent clock: pause/step/cache/seek/speed/reverse/hide/unload, display cap and legacy filter isolation.')
