import importlib.util
from pathlib import Path
from contextlib import contextmanager
import uuid
import unittest

spec=importlib.util.spec_from_file_location('capture_summary',Path(__file__).resolve().parents[1]/'scripts/summarize_mission6_capture.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

@contextmanager
def fixture_directory():
    # Use the writable workspace; retain tiny fixtures for inspection.
    path=Path(__file__).resolve().parents[1]/'build'/('mission6-summary-'+uuid.uuid4().hex)
    path.mkdir(parents=True)
    yield path

class SummaryTests(unittest.TestCase):
    def test_missing_and_aborted_footer_are_rejected(self):
        with fixture_directory() as folder:
            p=Path(folder)
            (p/'snapshot-1.tsv').write_text('value\tMission007.KeyIndexData[0]\tFName\tB\t\n')
            (p/'snapshot-2.tsv').write_text('summary\ttest\taborted\ttime_budget\tcontext_changed=false\n')
            result=module.summarize(p)['snapshots']
            self.assertTrue(all(not s['accepted_traversal'] for s in result))

    def test_completed_partial_sample_still_not_native_complete(self):
        with fixture_directory() as folder:
            p=Path(folder)
            (p/'snapshot-1.tsv').write_text('gap\tC.Map\tunsupported_wrapper\tTrivialObject\t\nsummary\ttest\ttraversal_finished\t\tgaps=1;context_changed=false\n')
            result=module.summarize(p)['snapshots'][0]
            self.assertTrue(result['accepted_traversal'])
            self.assertEqual(result['gaps'],{'unsupported_wrapper':1})
            self.assertFalse(result['native_graph_complete'])

if __name__=='__main__':unittest.main()
