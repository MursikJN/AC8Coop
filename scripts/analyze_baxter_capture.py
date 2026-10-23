"""Join same-session reflected event references by full name AND runtime address.

Output belongs in private evidence storage, never in a public repository.
No claim of an atomic snapshot or of native callback execution.
"""
import argparse
import csv
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path


def read_sample(path):
    with path.open(encoding='utf-8', newline='') as stream:
        rows=list(csv.DictReader(stream, delimiter='\t', quoting=csv.QUOTE_NONE))
    footer=next((r for r in reversed(rows) if r['kind']=='summary'), {})
    obj=next((r for r in rows if r['kind']=='object'), {})
    scope=next((r for r in rows if r['kind']=='scope'), {})
    return dict(file=path.name, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        accepted=footer.get('type_or_status')=='traversal_finished'
        and 'context_changed=false' in footer.get('detail',''),
        root=obj.get('path'),address=obj.get('value'),query=scope.get('path'),
        footer=footer,rows=rows)


def join_events(samples):
    targets={}
    for s in samples:
        if s['accepted'] and s['root'] and s['query']!='LiveEventContainer':
            targets[(s['root'],s['address'])]=s
    result=[]
    for s in samples:
        if not s['accepted'] or s['query']!='LiveEventContainer':continue
        entries=defaultdict(list)
        for r in s['rows']:
            m=re.search(r'\.ExecutionCollection\{entry(\d+)\}\.(.*)',r['path'])
            if m:entries[m[1]].append((m[2],r))
        world=next((r['value'] for r in s['rows'] if r['kind']=='reference'
                    and r['path'].endswith('.RelatedWorldData')),None)
        for entry in entries.values():
            key=next((r['value'] for suffix,r in entry if suffix=='key' and r['kind']=='value'),None)
            for suffix,r in entry:
                if r['kind']!='reference':continue
                target=targets.get((r['value'],r['detail']))
                if target:
                    result.append(dict(container_file=s['file'],world_data=world,event_key=key,
                        reference_path=suffix,target_file=target['file'],target=target['root'],
                        target_address=target['address'],fields=[
                            dict(field=v['path'][len(target['root'])+1:],kind=v['kind'],
                                 type=v['type_or_status'],value=v['value'])
                            for v in target['rows'] if v['kind'] in ('value','reference')]))
    return result


def analyze(directory):
    paths=sorted([*directory.glob('snapshot-*.tsv'),*directory.glob('watch-*.tsv')],
                 key=lambda p:int(p.stem.split('-')[1]))
    samples=[read_sample(p) for p in paths]
    changes=defaultdict(list)
    for s in samples:
        if not s['accepted'] or not s['file'].startswith('watch-'):continue
        for r in s['rows']:
            if r['kind']!='value':continue
            # Early watch writer collapsed false to an empty cell. It is unknown,
            # not a proven false value; ordinary snapshot writer was unaffected.
            if r['type_or_status']=='BoolProperty' and r['value']=='':continue
            k=(s['root'],s['address'],r['path'][len(s['root'])+1:])
            if not changes[k] or changes[k][-1]['value']!=r['value']:
                changes[k].append(dict(file=s['file'],value=r['value']))
    return dict(warning='Cross-file identity join only; not atomic; no execution or causality proof.',
        samples=[{k:v for k,v in s.items() if k!='rows'} for s in samples],
        event_links=join_events(samples),
        watch_changes=[dict(root=k[0],address=k[1],field=k[2],changes=v)
                       for k,v in changes.items() if len(v)>1])


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('directory',type=Path);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.write_text(json.dumps(analyze(a.directory),ensure_ascii=False,indent=2),encoding='utf-8')
