"""Paused replica loader's engine boundary; no game process or input injection."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts/steam_coop_client_world.lua'
FIXTURE=r'''
function yes()return true end
function name(v)return {ToString=function()return v end}end
MAIN={IsValid=yes,GetAddress=function()return 1 end,GetFullName=function()return 'World /Game/Maps/Menu/PL_MainMenu.PL_MainMenu'end}
MISSION={IsValid=yes,GetAddress=function()return 2 end,GetFullName=function()return 'World /Game/Maps/Ingame/Mission007/PL_Mission007.PL_Mission007'end}
CURRENT=MAIN;TIME=42;AX=1;TRAVELS=0;PAUSED=false;HIDDEN=0
PAWN={IsValid=yes,GetAddress=function()return 3 end,IsA=function()return false end,GetWorld=function()return CURRENT end}
PC={IsValid=yes,Pawn=PAWN,GetAddress=function()return 4 end,GetWorld=function()return CURRENT end}
MODE_NAME='Class /Script/Engine.GameModeBase'
MODE={IsValid=yes,GetAddress=function()return 5 end,GetWorld=function()return CURRENT end,GetClass=function()return {GetFullName=function()return MODE_NAME end}end}
AI={IsValid=yes,GetAddress=function()return 6 end,GetWorld=function()return CURRENT end,K2_GetActorLocation=function()return {X=AX,Y=2,Z=3}end}
FUNC={IsValid=yes,ForEachProperty=function(_,fn)
 for _,v in ipairs({{'WorldContextObject','ObjectProperty',0},{'LevelName','NameProperty',8},{'bAbsolute','BoolProperty',16},{'Options','StrProperty',24}})do
  local key,kind,off=table.unpack(v);fn({GetFName=function()return name(key)end,GetClass=function()return {GetFName=function()return name(kind)end}end,GetOffset_Internal=function()return off end})
 end
end}
GAME={IsGamePaused=function()return PAUSED end,GetTimeSeconds=function()return TIME end,OpenLevel=function(_,world,path,absolute,options)
 assert(world==MAIN and absolute==true and options=='game=/Script/Engine.GameModeBase');TRAVELS=TRAVELS+1
end}
API={player=function()return PC end,static=function(path)return path:find(':OpenLevel',1,true)and FUNC or GAME end,
 find=function(q)if q=='GameModeBase'then return {MODE}elseif q=='LiveGameObject'or q=='LiveAIGameObject'then return {AI}elseif q=='LiveMenuMainTopWidget'then return {{IsValid=yes,IsVisible=yes}}end;return {}end,
 pause={command=function()PAUSED=true;return {held='1',paused='1'}end},
 visibility={new=function()return {set=function(objects)HIDDEN=0;for _ in pairs(objects)do HIDDEN=HIDDEN+1 end end,stop=function()end}end}}
FName=function(s)return s end
C={role='guest',token='123',now=1000,snapshot={mission='6',difficulty='1',guest_aircraft='23',generation='1',revision='2'}}
io.open=function()return {write=function()end,close=function()end}end
'''
class ReplicaLoaderTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.execute(FIXTURE);self.l.globals().M=self.l.execute(SOURCE.read_text(encoding='utf-8'));self.l.execute("P=M.new(C,'out','source',function()end,API)")
 def test_travel_requested_once_and_never_connects_to_host_url(self):
  self.l.execute('assert(not P.prepare_flight(C.snapshot));P.prepare_flight(C.snapshot);assert(TRAVELS==1 and not P.context)')
 def test_wrong_game_mode_blocks_scene(self):
  self.l.execute("P.prepare_flight(C.snapshot);CURRENT=MISSION;MODE_NAME='Class /Script/Live.LiveGameMode';assert(not pcall(P.prepare_flight,C.snapshot));assert(not P.context)")
 def test_requires_observed_frozen_world_before_readiness(self):
  self.l.execute("P.prepare_flight(C.snapshot);CURRENT=MISSION;assert(not P.prepare_flight(C.snapshot));assert(not P.context.isolated_world_verified);for i=1,12 do C.now=C.now+100;P.prepare_flight(C.snapshot)end;assert(P.context.isolated_world_verified and P.verify(P.context) and HIDDEN==2)")
 def test_world_time_or_actor_movement_revokes_isolation(self):
  self.l.execute("P.prepare_flight(C.snapshot);CURRENT=MISSION;P.prepare_flight(C.snapshot);TIME=43;assert(not pcall(P.prepare_flight,C.snapshot));TIME=42;AX=2;assert(not pcall(P.prepare_flight,C.snapshot))")
 def test_new_sortie_cannot_reuse_context(self):
  self.l.execute("P.prepare_flight(C.snapshot);CURRENT=MISSION;P.prepare_flight(C.snapshot);for i=1,12 do C.now=C.now+100;P.prepare_flight(C.snapshot)end;C.snapshot.generation='2';assert(not P.verify(P.context))")
if __name__=='__main__':unittest.main()
