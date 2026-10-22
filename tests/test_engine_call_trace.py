"""Disk breadcrumbs survive an unreturned stage; preserve Lua call semantics."""
from pathlib import Path
import json, shutil, subprocess, tempfile, unittest, zipfile
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
class EngineTraceTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
  self.l=LuaRuntime(unpack_returned_tuples=True)
  self.l.globals().M=self.l.execute((ROOT/'probe/AC8CoopRecon/Scripts/engine_call_trace.lua').read_text())
  self.l.globals().OUT=Path(self.temp.name).as_posix();self.l.execute('T=M.new(OUT)')
 def test_entered_is_closed_and_readable_during_call(self):
  self.l.execute("""T.run('mission.update',function()
   T.run('cinema.discover',function()
    local f=assert(io.open(OUT..'/engine-call-current.tsv','rb'));local s=f:read('*a');f:close()
    assert(s:find('state\tentered',1,true)and s:find('mission.update > cinema.discover',1,true))
   end)
  end)""")
 def test_nil_and_multiple_results_preserved(self):
  self.l.execute("local a,b,c=T.run('sample',function(a)return a,nil,42 end,false);assert(a==false and b==nil and c==42)")
 def test_errors_unwind_trace_and_propagate(self):
  self.l.execute("assert(not pcall(T.run,'bad',function()error('sentinel')end));T.run('next',function()end)")
  s=(Path(self.temp.name)/'engine-call-current.tsv').read_text();self.assertIn('path\tnext\n',s)
 def test_bounded_size_and_field_sanitization(self):
  self.l.execute(r"for i=1,250 do T.run(string.rep('x',1000)..'\n\t',function()end)end")
  p=Path(self.temp.name)/'engine-call-current.tsv';self.assertLess(p.stat().st_size,512)
  self.assertEqual(len(p.read_text().splitlines()),6)
 def test_existing_automatic_report_collector_includes_breadcrumb(self):
  self.l.execute("T.run('cinema.discover',function()end)")
  base=Path(self.temp.name);session=base/'session';(session/'mod').mkdir(parents=True)
  (session/'session.json').write_text(json.dumps({'role':'host','revision':'r31-development'}))
  shutil.copyfile(base/'engine-call-current.tsv',session/'mod/engine-call-current.tsv')
  r=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'coop/Collect-CoopLogs.ps1'),'-SessionDirectory',str(session),'-ReportsDirectory',str(base/'reports')],capture_output=True)
  self.assertEqual(r.returncode,0,r.stderr.decode(errors='replace'))
  with zipfile.ZipFile(next((base/'reports').glob('*.zip')))as z:
   name=next(n for n in z.namelist()if n.endswith('/engine-call-current.tsv'))
   self.assertEqual(z.read(name),(base/'engine-call-current.tsv').read_bytes())
if __name__=='__main__':unittest.main()
