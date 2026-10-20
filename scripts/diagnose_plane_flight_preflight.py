"""Read-only reproduction of native preflight predicates; never calls game code."""
from datetime import datetime
import json
from pathlib import Path
import struct
from sample_plane_motion import WindowsReader
from sample_plane_configuration import ConfigurationReader

SESSION = Path(r'D:\projects\unreal-mod-tools\profiles\ac8-build25201480\evidence\session-20261020-094212')

def main():
    session = json.loads((SESSION/'session.json').read_text(encoding='utf-8-sig'))
    assert session['pid'] == 55764 and session['exit_code'] is None
    fields = dict(line.split('\t', 1) for line in (SESSION/'plane-flight-request.tsv').read_text().splitlines())
    ticket = {key: int(fields[key], 0) for key in ['world','controller','pawn','pc_pawn_offset','plane_controller_offset']}
    ticket['pawn_class'] = int(fields['plane_class'], 0)
    reader = WindowsReader(session['pid'], datetime.fromisoformat(session['started']).timestamp())
    reads, checks = {}, []
    def read(address, size):
        result = reader.read(address, size)
        reads[f'{address:#x}:{size}'] = result.hex()
        return result
    def value(address, fmt):
        return struct.unpack('<'+fmt, read(address, struct.calcsize('<'+fmt)))[0]
    def check(name, actual, expected):
        checks.append(dict(name=name, actual=actual, expected=expected, passed=actual == expected))
    try:
        probe = ConfigurationReader(read, reader.base, ticket)
        p,w,cl,pc = (ticket[k] for k in ['pawn','world','pawn_class','controller'])
        cdo = value(cl+0x110, 'Q')
        check('world_type', value(w+0x13a,'B'),1)
        check('pawn_vtable', value(p,'Q'),reader.base+0xcc01cc8)
        check('cdo_vtable', value(cdo,'Q'),reader.base+0xcc01cc8)
        check('cdo_class',value(cdo+0x10,'Q'),cl)
        check('cdo_flag',bool(value(cdo+8,'I')&0x10),True)
        objects={}
        for i,(name,addr) in enumerate([('world',w),('controller',pc),('pawn',p),('class',cl),('cdo',cdo)]):
            objects[name]=probe.object(addr)
            if i<3:
                check(name+'_serial_positive',objects[name]['serial']>0,True)
                check(name+'_not_destroyed',bool(value(addr+8,'I')&0x40000000),False)
        level=value(w+0x30,'Q'); outer=value(p+0x20,'Q')
        check('spawn_level_world',value(level+0xc0,'Q'),w)
        check('pawn_level_world',value(outer+0xc0,'Q'),w)
        check('world_construction',bool(value(w+0x13c,'B')&2),False)
        check('world_teardown',bool(value(w+0x13d,'B')&0x20),False)
        check('pawn_pending',bool(value(p+0x5d,'B')&1),False)
        gi=value(w+0x1d8,'Q'); act=value(p+0x16a8,'Q'); weapon=value(act+0x2e0,'Q'); parts=value(p+0x1328,'Q')
        configs=[('parts',parts,p),('activator',act,p),('target',value(p+0x1ae8,'Q'),p),('indicator',value(p+0x18d8,'Q'),p),('weapon',weapon,p),('nested',value(weapon+0xa8,'Q'),p),('extra',value(act+0x2e8,'Q'),act),('metadata',value(gi+0x878,'Q'),None),('gameinstance',gi,None),('strix',value(gi+0x910,'Q'),None)]
        for name,addr,expected_outer in configs:
            objects[name]=probe.object(addr)
            if expected_outer is not None: check(name+'_outer',int(objects[name]['outer'],0),expected_outer)
            if name=='gameinstance': check('gameinstance_serial_positive',objects[name]['serial']>0,True)
        arrays={}
        for name,addr,cap in [('parts',parts+0x30,16),('other',parts+0x40,16),('cosmetics',p+0xfb8,32)]:
            arrays[name]=probe.array(addr,4,cap)
            check(name+'_capacity_native_limit',arrays[name]['capacity']<=4096,True)
            if name!='parts': check(name+'_empty',arrays[name]['count'],0)
        check('parts_effects_empty',value(parts+0x1a7f0,'i'),0)
        check('selected_row',value(p+0x3ab8,'i'),0)
        registry=probe.registry(gi)
        check('auto_init_disabled',registry['auto_init_flag_1fa'],0)
        check('owned_id_absent',registry['candidates'][0]['present'],False)
        for obj in objects.values(): probe.object(int(obj['address'],0))
        probe.check_identity()
        result=dict(read_only=True,pid=session['pid'],stamp=fields['stamp'],checks=checks,objects=objects,arrays=arrays,registry=registry,reads=reads,failed=[c for c in checks if not c['passed']],native_bridge_not_executed=True)
        (SESSION/'plane-flight-preflight-diagnosis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(json.dumps({'checks':len(checks),'failed':result['failed'],'result_file':str(SESSION/'plane-flight-preflight-diagnosis.json')}))
        return 1 if result['failed'] else 0
    finally:
        reader.close()

if __name__=='__main__': raise SystemExit(main())
