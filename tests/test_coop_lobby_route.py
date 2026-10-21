"""Route refusal, transition ordering and one-shot behavior with recorded bridge replies."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts/coop_lobby_route.lua'
class RouteTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.globals().M=self.l.execute(SOURCE.read_text(encoding='utf-8'))
  self.l.execute('''
T=0;CAP=true;FLIGHT=false;CURRENT=1;AVAILABLE=false;REASON=nil;CONFIRMS=0;SELECTS=0;CLOSES=0
A={now=function()return T end,capable=function()return CAP end,close=function()CLOSES=CLOSES+1 end,log=function()end,flight_supported=function()return FLIGHT end,
find=function(query)if M.steps[CURRENT]and query==M.steps[CURRENT][2]then return 'object-'..CURRENT end end,
command=function(op,kind,object)
 if op=='inspect'then return {status=REASON and 'refused'or'verified',reason=REASON or(AVAILABLE and'target_available'or'target_selected')}end
 if op=='select'then SELECTS=SELECTS+1;AVAILABLE=false;return {status='selected'}end
 CONFIRMS=CONFIRMS+1;CURRENT=CURRENT+1;return {status='returned',returned='1'}
end};R=M.new(A)
''')
 def runlua(self,s):self.l.execute(s)
 def val(self,s):return self.l.eval(s)
 def test_all_native_steps_before_flight(self):
  self.runlua('R.begin(7,23,1);for i=1,#M.steps do R.update()end;FLIGHT=true;R.update()')
  self.assertEqual(self.val('R.phase'),'flight');self.assertEqual(self.val('CONFIRMS'),self.val('#M.steps'))
 def test_only_fixed_configuration(self):
  self.assertFalse(self.val('R.supported(6,23)'));self.assertFalse(self.val('R.supported(7,22)'))
 def test_no_second_launch(self):
  self.runlua('R.begin(7,23,1)');self.assertRaises(Exception,self.runlua,'R.begin(7,23,2)')
 def test_selection_and_confirm_share_callback_to_avoid_hover_race(self):
  self.runlua('R.begin(7,23,1);AVAILABLE=true;R.update()')
  self.assertEqual(self.val('SELECTS'),1);self.assertEqual(self.val('CONFIRMS'),1)
 def test_fingerprint_refusal_never_confirms(self):
  self.runlua("R.begin(7,23,1);REASON='confirm_fingerprint'")
  self.assertRaises(Exception,self.runlua,'R.update()');self.assertEqual(self.val('CONFIRMS'),0)
 def test_native_animation_waits_without_mutation(self):
  self.runlua("R.begin(7,23,1);REASON='widget_or_selection_contract';for i=1,10 do R.update()end")
  self.assertEqual(self.val('CONFIRMS+SELECTS'),0)
 def test_reselection_refused(self):
  self.runlua('R.begin(7,23,1);AVAILABLE=true;R.update();R.step=1;CURRENT=1;AVAILABLE=true')
  self.assertRaises(Exception,self.runlua,'R.update()');self.assertEqual(self.val('SELECTS'),1)
 def test_loading_timeout(self):
  self.runlua('R.begin(7,23,1);T=601');self.assertRaises(Exception,self.runlua,'R.update()')
 def test_unexpected_early_flight_refused(self):
  self.runlua('R.begin(7,23,1);FLIGHT=true');self.assertRaises(Exception,self.runlua,'R.update()')
if __name__=='__main__':unittest.main()
