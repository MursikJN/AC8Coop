"""Meaningful guards around native travel, separate from the old menu macros."""
import tempfile
import unittest
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'probe/AC8CoopRecon/Scripts/shared_session_guest_trial.lua'

class NativeGuestTrialTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
        local function object(name)
          return {IsValid=function()return true end,GetFullName=function()return name end}
        end
        env={AC8_COOP_RECON='1',AC8_NATIVE_HOST_STEAM_ID='76561198064023082'}
        os.getenv=function(n)return env[n]end
        function FName(s)return {ToString=function()return s end}end
        world=object('World /Game/Maps/Menu/PL_MainMenu.PL_MainMenu')
        pc=object('Controller');pc.GetWorld=function()return world end
        definition={DefName=FName('GameNetDriver'),DriverClassName=FName('OnlineSubsystemEOS.NetDriverEOS'),DriverClassNameFallback=FName('OnlineSubsystemUtils.IpNetDriver')}
        definitions={definition};definitions.GetArrayNum=function()return 1 end
        engine=object('Engine');engine.NetDriverDefinitions=definitions
        package.preload.UEHelpers=function()return {GetPlayerController=function()return pc end}end
        FindAllOf=function(n)assert(n=='LiveGameEngine');return {engine}end
        calls={}
        library=object('GameplayStatics')
        library.OpenLevel=function(self,w,level,absolute,options)
          calls[#calls+1]={world=w,url=level:ToString(),absolute=absolute,options=options}
        end
        signature={{'WorldContextObject','ObjectProperty',0},{'LevelName','NameProperty',8},{'bAbsolute','BoolProperty',16},{'Options','StrProperty',24}}
        fn=object('OpenLevel')
        fn.ForEachProperty=function(self,callback)
          for _,v in ipairs(signature)do
            callback({GetFName=function()return FName(v[1])end,GetClass=function()return {GetFName=function()return FName(v[2])end}end,GetOffset_Internal=function()return v[3]end})
          end
        end
        StaticFindObject=function(n)
          if n=='/Script/Engine.GameplayStatics:OpenLevel'then return fn end
          if n=='/Script/Engine.Default__GameplayStatics'then return library end
          if n=='/Script/OnlineSubsystemSteam.SteamNetDriver'then return object('SteamNetDriver')end
          error('Unexpected engine lookup '..n)
        end
        ''')
        self.run_trial = self.lua.execute(SOURCE.read_text())

    def trial(self):
        return self.run_trial(self.folder.name.replace('\\','/'), 'unit')

    def assert_untouched(self):
        self.assertEqual(self.lua.eval('#calls'), 0)
        self.assertEqual(self.lua.eval('definition.DriverClassName:ToString()'), 'OnlineSubsystemEOS.NetDriverEOS')

    def test_success_uses_native_server_url_once(self):
        self.trial()
        self.assertEqual(self.lua.eval('#calls'), 1)
        self.assertEqual(self.lua.eval('calls[1].url'), 'steam.76561198064023082:7777')
        self.assertTrue(self.lua.eval('calls[1].absolute'))
        self.assertEqual(self.lua.eval('calls[1].options'), '')
        self.assertEqual(self.lua.eval('definition.DriverClassName:ToString()'), '/Script/OnlineSubsystemSteam.SteamNetDriver')
        with self.assertRaises(Exception): self.trial()
        self.assertEqual(self.lua.eval('#calls'), 1)

    def test_wrong_world_never_changes_transport_or_travels(self):
        self.lua.execute("world.GetFullName=function()return 'World /Game/Maps/Mission/Mission007' end")
        with self.assertRaises(Exception): self.trial()
        self.assert_untouched()

    def test_existing_connection_never_replaced(self):
        self.lua.execute('world.NetDriver={IsValid=function()return true end}')
        with self.assertRaises(Exception): self.trial()
        self.assert_untouched()

    def test_signature_drift_rejected_before_mutation(self):
        self.lua.execute('signature[4][3]=32')
        with self.assertRaises(Exception): self.trial()
        self.assert_untouched()

    def test_invalid_host_rejected_before_mutation(self):
        self.lua.execute("env.AC8_NATIVE_HOST_STEAM_ID='steam.76561198064023082:7777?listen'")
        with self.assertRaises(Exception): self.trial()
        self.assert_untouched()

class NativeObserverTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory();self.addCleanup(self.folder.cleanup)
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        function object(n)return {IsValid=function()return true end,GetFullName=function()return n end}end
        function array(n)return setmetatable({GetArrayNum=function()return n end},{__index=function(t,k)return object('Entry'..k)end})end
        world=object('World MainMenu');pc=object('Controller');pc.GetWorld=function()return world end
        gs=object('GameState');gs.PlayerArray=array(1);world.GameState=gs
        driver=object('SteamNetDriver');driver.ClientConnections=array(0);driver.NetConnectionClassName='SteamNetConnection'
        drivers={driver}
        FindAllOf=function(n)assert(n=='NetDriver');return drivers end
        package.preload.UEHelpers=function()return {GetPlayerController=function()return pc end}end
        ExecuteInGameThreadWithDelay=function(delay,callback)assert(delay==1000);next_callback=callback end
        ''')
        self.observer=self.lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/shared_session_connection_observer.lua').read_text())

    def status(self):
        return (Path(self.folder.name)/'native-connection-status.tsv').read_text()

    def start(self,role='guest'):
        self.observer(self.folder.name.replace('\\','/'),role)

    def test_disappearing_pending_driver_reports_failure(self):
        self.start();self.assertIn('phase\tguest_connecting',self.status())
        self.lua.execute('drivers={};next_callback()')
        self.assertIn('phase\tguest_connection_failed',self.status())

    def test_native_error_preserved_even_without_pending_driver(self):
        self.lua.execute("drivers={};AC8NativeLastFailure={kind='network',code=4,at=123}")
        self.start();self.assertIn('phase\tguest_connection_failed',self.status())
        self.assertIn('failure_code\t4',self.status())

    def test_server_with_no_guest_does_not_claim_two_players(self):
        self.lua.execute('world.NetDriver=driver')
        self.start('host');self.assertIn('phase\thost_waiting',self.status())
        self.assertNotIn('two_players_observed',self.status())

    def test_guest_requires_native_server_connection_and_two_players(self):
        self.lua.execute("world.NetDriver=driver;driver.ServerConnection=object('NativeServerConnection');gs.PlayerArray=array(2)")
        self.start();self.assertIn('phase\tguest_has_native_server',self.status())
        self.assertIn('two_players_observed\ttrue',self.status())

if __name__ == '__main__':
    unittest.main()
