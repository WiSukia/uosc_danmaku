"""Check actual local-rule Lua with positive examples and false-positive boundaries."""
from pathlib import Path
import json
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
rules=lua.execute((ROOT/'modules/autofilter.lua').read_text(encoding='utf-8'))
cases=json.loads((ROOT/'tests/autofilter-cases.json').read_text(encoding='utf-8'))
for case in cases:
    enabled=lua.table_from({'date':False,'people':False,'group':False})
    enabled[case['rule']]=True
    result=rules.matches(case['text'],enabled)
    if isinstance(result,tuple):result=result[0]
    assert result is case['expected'],case
    enabled[case['rule']]=False
    assert rules.matches(case['text'],enabled) is False,case
print(f'PASS {len(cases)} automatic-rule examples and {len(cases)} individual-disable cases.')
