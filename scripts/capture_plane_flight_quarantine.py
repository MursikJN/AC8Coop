"""Bounded VM_READ capture of the owned r2 actor; no engine calls or writes."""
from datetime import datetime
import json
import struct
from diagnose_plane_flight_preflight import SESSION
from sample_plane_motion import WindowsReader
from sample_plane_configuration import ConfigurationReader

def main():
    session=json.loads((SESSION/'session.json').read_text(encoding='utf-8-sig'))
    status=dict(line.split('\t',1) for line in (SESSION/'plane-flight-status.tsv').read_text().splitlines())
    request=dict(line.split('\t',1) for line in (SESSION/'plane-flight-request.tsv').read_text().splitlines())
    assert session['exit_code'] is None and status['module_revision']=='r2' and status['status']=='quarantine'
    t={k:int(request[k],0) for k in ['world','controller','pawn','pc_pawn_offset','plane_controller_offset']}
    t['pawn_class']=int(request['plane_class'],0)
    reader=WindowsReader(session['pid'],datetime.fromisoformat(session['started']).timestamp())
    result={'read_only':True,'pid':session['pid'],'status':status,'checks':[],'reads':{}}
    def read(p,n):
        data=reader.read(p,n);result['reads'][f'{p:#x}:{n}']=data.hex();return data
    def v(p,fmt):return struct.unpack('<'+fmt,read(p,struct.calcsize('<'+fmt)))[0]
    def check(name,actual,expected):result['checks'].append(dict(name=name,actual=actual,expected=expected,passed=actual==expected))
    try:
        probe=ConfigurationReader(read,reader.base,t)
        p=int(status['owned'],0);own=probe.object(p)
        assert own['index']==int(status['index']) and own['serial']==int(status['serial'])
        result['owned']=own;result['objects']={}
        for name,addr in [('plane',p),('network',int(status['network'],0)),('parts',int(status['parts'],0))]:result['objects'][name]=probe.object(addr)
        for name,off,fmt in [('active',0x3f4,'B'),('tick_state',0x33,'B'),('auto_player',0x2a0,'B'),('auto_ai',0x2a1,'B'),('controller',0x2c8,'Q')]:check(name,v(p+off,fmt),0)
        check('begun_mask',v(p+0x5d,'B')&12,8);check('network_role',v(p+0xed8,'B'),2)
        check('network_id',v(int(status['network'],0)+0x28,'Q'),0x434f4f5000000001)
        objects={}
        for name,off in [('activator',0x16a8),('target',0x1ae8),('indicator',0x18d8)]:
            addr=v(p+off,'Q');objects[name]=addr
            if addr:
                obj=probe.object(addr);result['objects'][name]=obj
                check(name+'_outer',int(obj['outer'],0),p)
                src=probe.object(v(t['pawn']+off,'Q'));check(name+'_class',obj['klass'],src['klass'])
            else:check(name+'_nonnull',False,True)
        act=objects['activator']; target=objects['target'];indicator=objects['indicator']
        if indicator:check('indicator_backlink',v(indicator+0x1c0,'Q'),p)
        check('bp_indicator',v(p+0x5a08,'Q'),indicator);check('bp_target',v(p+0x5a30,'Q'),target)
        if act:
            check('activator_plane',v(act+0x2d0,'Q'),p);check('activator_target',v(act+0x2d8,'Q'),target);check('activator_initialized',v(act+0x579,'B'),1)
            for name,addr,parent in [('weapon',v(act+0x2e0,'Q'),p),('extra',v(act+0x2e8,'Q'),act)]:
                objects[name]=addr
                if addr:result['objects'][name]=probe.object(addr);check(name+'_outer',int(result['objects'][name]['outer'],0),parent)
                else:check(name+'_nonnull',False,True)
            if objects['weapon']:
                addr=v(objects['weapon']+0xa8,'Q');check('nested_nonnull',bool(addr),True)
                if addr:result['objects']['nested']=probe.object(addr);check('nested_outer',int(result['objects']['nested']['outer'],0),p)
        table=v(p+0x3ab0,'Q');result['table']={'address':hex(table),'row':v(p+0x3ab8,'i')}
        if table:result['table'].update(data=hex(v(table+0x18,'Q')),count=v(table+0x20,'i'))
        raw=read(p+0x218,0x50);data,num,capacity=struct.unpack_from('<Qii',raw);external=struct.unpack_from('<Q',raw,0x20)[0];bits,maxbits=struct.unpack_from('<ii',raw,0x28);free=struct.unpack_from('<i',raw,0x34)[0]
        result['component_set']={'raw':raw.hex(),'data':hex(data),'num':num,'capacity':capacity,'external':hex(external),'bits':bits,'maxbits':maxbits,'free':free}
        result['components']=[]
        check('component_set_bounds',0<=free<=num<=512 and bits==num and num<=capacity<=4096 and bits<=maxbits<=4096 and (external!=0 or bits<=128),True)
        if result['checks'][-1]['passed']:
            root=v(reader.base+0xe4addd8,'Q');idx=v(root+0x38,'i');result['component_root']={'address':hex(root),'index':idx};assert 0<=idx<1024
            for i in range(bits):
                bitmap=external or p+0x228
                if not (v(bitmap+(i//32)*4,'I')&(1<<(i%32))):continue
                c=v(data+i*16,'Q');obj=probe.object(c);vt=v(c,'Q');cl=int(obj['klass'],0);count=v(cl+0x38,'i');chain=v(cl+0x30,'Q')
                record={'index':i,'object':obj,'owner90':hex(v(c+0x90,'Q')),'setter':hex(v(vt+0x3d8,'Q')),'getter':hex(v(vt+0x3e8,'Q')),'tick3b':v(c+0x3b,'B'),'class_chain_count':count}
                result['components'].append(record)
                check(f'component_{i}_is_a',count>=idx and count<1024 and v(chain+idx*8,'Q')==root+0x30,True)
                check(f'component_{i}_owner',int(record['owner90'],0),p)
                check(f'component_{i}_setter',int(record['setter'],0),reader.base+0x41df200)
                check(f'component_{i}_getter',int(record['getter'],0),reader.base+0x41df3e0)
                check(f'component_{i}_tick',record['tick3b'],0)
            check('component_set_unchanged',read(p+0x218,0x50)==raw,True)
        result['registry']=probe.registry(v(t['world']+0x1d8,'Q'))
        probe.check_identity();assert probe.object(p)==own
        result['failed']=[c for c in result['checks'] if not c['passed']]
        result['result']='capture_complete'
    except Exception as exc:
        result['result']='partial';result['error']=str(exc)
        raise
    finally:
        (SESSION/'plane-flight-r2-quarantine-capture.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        reader.close()
        print(json.dumps({k:result[k] for k in ['result','failed','error'] if k in result}))

if __name__=='__main__':main()
