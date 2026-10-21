"""Host-only native route, verified guest slot, and second readiness before sortie."""
from pathlib import Path
import unittest
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'probe/AC8CoopRecon/Scripts/local_hangar_adapter.lua'


class HangarAdapterTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            STEPS={};SORTIES=0;VERIFIED=0;MARKED=0;MAP=true;FLIGHT=false;NOW=0
            os.time=function()return NOW end
            local object={IsValid=function()return true end}
            N={find=function(query)if query=='LiveMenuHangarStandbyWidget'and STANDBY==false then return nil end;return object end,
             command=function()return {status='verified',selected=HOST or '7010',value=MAP and '23010'or'7010'}end,
             step=function(kind)STEPS[#STEPS+1]=kind;if kind=='sortie'then SORTIES=SORTIES+1 end;return true end}
            U={attach=function()return {refresh=function()return true end,close=function()end}end}
            loadfile=function(path)return function()return path:find('local_menu_native',1,true)and {new=function()return N end}or U end end
            C={snapshot={phase='0',mission='6',difficulty='1',guest_aircraft='23'},pending=nil}
            C.view=function()return {can_start_flight=C.snapshot.phase=='4'and C.snapshot.ready_mask=='3'}end
            C.hangar_verified=function(a,b)assert(a==7 and b==23);VERIFIED=VERIFIED+1;C.snapshot.host_aircraft=tostring(a);C.snapshot.phase='4';C.snapshot.ready_mask='0'end
            C.start_flight=function()C.snapshot.phase='5'end
            C.flight_verified=function()MARKED=MARKED+1;C.snapshot.phase='6'end
            C.status=function()return 'hangar'end
            FindAllOf=function()if not FLIGHT then return {}end;return {{IsValid=function()return true end,
                Pawn={IsValid=function()return true end,IsA=function()return true end,GetClass=function()return {GetFullName=function()return '/PP0007_fa18c/BP_Player'end}end},
                GetWorld=function()return {IsValid=function()return true end,GetFullName=function()return '/Game/Mission007'end}end}}end
        ''')
        self.lua.globals().M = self.lua.execute(SOURCE.read_text(encoding='utf-8'))
        self.lua.execute("A=M.new(C,'output','source',function()end)")
        # Avoid real fixture output; native calls are already replaced above.
        self.lua.execute("io.open=function()return {write=function()end,close=function()end}end")

    def runlua(self, code):
        self.lua.execute(code)

    def value(self, code):
        return self.lua.eval(code)

    def enter_hangar(self):
        self.runlua("C.snapshot.phase='3';for i=1,#M.steps+1 do A.update()end")

    def test_lobby_never_advances_menus_automatically(self):
        self.runlua('for i=1,10 do A.update()end')
        self.assertEqual(self.value('#STEPS'), 0)

    def test_guest_choice_is_applied_after_player_before_standby(self):
        self.enter_hangar()
        self.assertEqual(self.value('VERIFIED'), 1)
        self.assertEqual(self.value("C.snapshot.phase"), '4')
        self.assertEqual(self.value("C.snapshot.ready_mask"), '0')
        self.assertNotIn('aircraft_host_f14', [self.value('STEPS[%d]' % i) for i in range(1, int(self.value('#STEPS'))+1)])
        self.assertEqual(self.value('STEPS[9]'), 'aircraft_guest_f14')
        self.assertEqual(self.value('STEPS[#STEPS]'), 'aircraft_guest_f14')
        self.assertEqual(self.value('SORTIES'), 0)

    def test_wrong_guest_engine_plane_refuses_completion(self):
        self.runlua('MAP=false')
        self.enter_hangar()
        self.assertEqual(self.value('VERIFIED'), 0)
        self.assertEqual(self.value('A.phase'), 'error')
        self.assertEqual(self.value('SORTIES'), 0)

    def test_sortie_requires_new_readiness_and_explicit_host_start(self):
        self.enter_hangar()
        self.assertRaises(Exception, self.runlua, 'A.start()')
        self.runlua("C.snapshot.ready_mask='2'")
        self.assertRaises(Exception, self.runlua, 'A.start()')
        self.runlua("C.snapshot.ready_mask='3';A.update()")
        self.assertEqual(self.value('SORTIES'), 0)
        self.runlua('A.start();A.update();A.update()')
        self.assertEqual(self.value('SORTIES'), 1)
        self.assertEqual(self.value('MARKED'), 0)
        self.runlua('FLIGHT=true;A.update();A.update()')
        self.assertEqual(self.value('MARKED'), 1)

    def test_disconnect_during_route_stops_further_menu_commands(self):
        self.runlua("C.snapshot.phase='3';A.update();C.snapshot.phase='8';A.update()")
        self.assertEqual(self.value('#STEPS'), 1)
        self.assertEqual(self.value('A.phase'), 'stopped')

    def test_unsupported_mission_never_invokes_native_menu(self):
        self.runlua("C.snapshot.mission='1';C.snapshot.phase='3';A.update()")
        self.assertEqual(self.value('#STEPS'), 0)
        self.assertEqual(self.value('A.phase'), 'error')

    def test_manual_host_choice_waits_without_timeout_or_forcing_aircraft(self):
        self.runlua("C.snapshot.phase='3';for i=1,7 do A.update()end;HOST='23010';NOW=900;A.update()")
        self.assertEqual(self.value('A.step'), 8)
        self.assertIsNone(self.value('A.error'))
        self.assertEqual(self.value('VERIFIED'), 0)
        self.runlua("HOST='7010';A.update()")
        self.assertEqual(self.value('A.step'), 9)
        self.assertEqual(self.value('#STEPS'), 7)

    def test_explicit_squad_standby_route_is_retained_when_not_already_open(self):
        self.runlua("STANDBY=false;C.snapshot.phase='3';for i=1,#M.steps do A.update()end")
        self.assertEqual(self.value('STEPS[#STEPS]'), 'squad_standby')
        self.assertEqual(self.value('VERIFIED'), 0)
        self.runlua('STANDBY=true;A.update()')
        self.assertEqual(self.value('VERIFIED'), 1)

    def test_visible_standby_transition_waits_and_recovers(self):
        self.runlua("C.snapshot.phase='3';A.step=12;A.started=0;local original=N.command;N.command=function(...)if TRANSITION then return {status='refused',reason='hangar_loadout_contract'}end;return original(...)end;TRANSITION=true;A.update()")
        self.assertIsNone(self.value('A.error'))
        self.assertEqual(self.value('A.phase'), 'waiting_hangar_verification')
        self.assertEqual(self.value('VERIFIED'), 0)
        self.runlua('NOW=1;TRANSITION=false;A.update()')
        self.assertIsNone(self.value('A.error'))
        self.assertEqual(self.value('VERIFIED'), 1)

    def test_persistent_standby_contract_failure_never_launches(self):
        self.runlua("C.snapshot.phase='3';A.step=12;A.started=0;N.command=function()return {status='refused',reason='hangar_loadout_contract'}end;A.update();NOW=11;A.update()")
        self.assertEqual(self.value('A.phase'), 'error')
        self.assertEqual(self.value('VERIFIED'), 0)
        self.assertEqual(self.value('SORTIES'), 0)
