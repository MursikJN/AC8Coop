import sys
import unittest
import uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from analyze_baxter_capture import join_events, analyze

class IdentityJoinTests(unittest.TestCase):
    def test_rejects_same_name_different_address_and_unfinished_samples(self):
        target=dict(accepted=True,query='Action',root='Action A',address='0x2',file='target',rows=[])
        rows=[dict(kind='value',path='C.ExecutionCollection{entry7}.key',value='EventA'),
              dict(kind='reference',path='C.ExecutionCollection{entry7}.value.ExecutionInstanceList[0]',value='Action A',detail='0x1')]
        c=dict(accepted=True,query='LiveEventContainer',root='C',address='0x3',file='container',rows=rows)
        self.assertEqual(join_events([target,c]),[])
        rows[1]['detail']='0x2'
        self.assertEqual(join_events([target,c])[0]['event_key'],'EventA')
        target['accepted']=False
        self.assertEqual(join_events([target,c]),[])

    def test_legacy_blank_boolean_is_not_a_false_transition(self):
        scratch=Path(__file__).resolve().parents[1]/'build'
        scratch.mkdir(exist_ok=True)
        root=scratch/('baxter-analysis-test-'+uuid.uuid4().hex)
        root.mkdir()
        try:
            for n,value in enumerate(('true',''),1):
                (root/f'watch-{n:05}.tsv').write_text(
                    'kind\tpath\ttype_or_status\tvalue\tdetail\n'
                    'scope\tState\tsingle_root\tState A\t\n'
                    'object\tState A\taddress\t0x1\t\n'
                    f'value\tState A.Enabled\tBoolProperty\t{value}\t\n'
                    'summary\twatch\ttraversal_finished\t\tcontext_changed=false\n',
                    encoding='utf-8')
            self.assertEqual(analyze(root)['watch_changes'],[])
        finally:
            for n in (1,2):
                (root/f'watch-{n:05}.tsv').unlink(missing_ok=True)
            root.rmdir()

if __name__=='__main__':unittest.main()
