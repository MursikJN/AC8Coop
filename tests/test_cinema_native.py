"""Native adapter contract tests. Fake UObjects are not in-game AV evidence."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts/cinema_native.lua'
FIXTURE=r'''
function yes()return true end
function n(s)return {ToString=function()return s end}end
function asset(s)return {IsValid=yes,GetFullName=function()return 'Object '..s end}end
TEX=asset('/Game/T.T');CAM=asset('/Game/C.C');MEDIA=asset('/Game/Movies/Briefing.Briefing')
WORLD={IsValid=yes,GetAddress=function()return 1 end}
TARGET={IsValid=yes,GetWorld=function()return WORLD end}
PC={IsValid=yes,GetWorld=function()return WORLD end,GetViewTarget=function()return TARGET end,SetViewTargetWithBlend=function()RESTORED=true end}
READY=true;PREPARING=false;ERR=false;SELECTED_AUDIO=0;VIDEOS=1;AUDIOS=1;TIME=0;PAUSED=true;ISPLAYING=false;PLAYS=0;STOPS=0;CLOSES=0
PLAYER={IsValid=yes,GetAddress=function()return 12 end,HasError=function()return ERR end,IsReady=function()return READY end,IsPreparing=function()return PREPARING end,
 GetNumTracks=function(_,type)return type==1 and VIDEOS or AUDIOS end,GetSelectedTrack=function(_,type)return type==1 and 0 or SELECTED_AUDIO end,
 IsPlaying=function()return ISPLAYING end,IsPaused=function()return PAUSED end,GetDuration=function()return {opaque_seconds=DURATION or 10}end,
 Play=function()PLAYS=PLAYS+1;ISPLAYING=true;PAUSED=false;return true end}
CLASS={IsValid=yes,GetFullName=function()return 'WidgetBlueprintGeneratedClass /Game/UI/Movie.Movie_C'end,IsChildOf=yes}
VIEWER={IsValid=yes,GetAddress=function()return 11 end,GetWorld=function()return WORLD end,IsVisible=yes,GetClass=function()return CLASS end,
 IsA=yes,IsInViewport=function()return VISIBLE~=false end,GetParent=function()return PARENT end,GetOuter=function()return nil end,
 ManaTexture=TEX,PlayingManaSource=MEDIA,GetManaPlayer=function()return PLAYER end,GetTimeSeconds=function()return TIME end,
 PauseMovie=function()if not FAIL_PAUSE then PAUSED=true;ISPLAYING=false end end,StopMovie=function()STOPS=STOPS+1 end,
 CloseMovie=function()CLOSES=CLOSES+1 end,RemoveFromParent=function()REMOVED=true end,
 SetMediaSource=function(_,source,auto)OPEN_SOURCE=source;AUTO=auto end,SetVisibility=function()end}
SLOT={SetAnchors=function()end,SetOffsets=function()end,SetZOrder=function()end,SetPosition=function()end,SetSize=function()end}
ROOT={IsValid=yes,IsA=yes,GetChildrenCount=function()return 0 end,AddChildToCanvas=function()return SLOT end,SetVisibility=function()end}
SURFACE_CLASS=asset('/Game/Blueprints/UI/Cinematics/WBP_Cinema_SkipButton_000.WBP_Cinema_SkipButton_000_C')
SURFACE={IsValid=yes,WidgetTree={IsValid=yes},RootPanel=ROOT,SetVisibility=function()end,AddToViewport=function()MOUNTED=true end,RemoveFromParent=function()SURFACE_REMOVED=true end}
TEXT_CLASS={IsValid=yes};LABEL={IsValid=yes,Font={},SetVisibility=function()end,SetText=function(_,s)STATUS_TEXT=s end}
MAIN={IsValid=yes,IsVisible=yes,WidgetTree={IsValid=yes,RootWidget={IsValid=yes,IsA=yes,AddChildToCanvas=function()return SLOT end}}}
ENUM={IsValid=yes,ForEachName=function(_,fn)fn(n('EManaPlayerTrack::Video'),1);fn(n('EManaPlayerTrack::Audio'),2)end}
SPECS={GetTotalSeconds='A:StructProperty,ReturnValue:FloatProperty',PauseMovie='',StopMovie='',CloseMovie='',GetManaPlayer='ReturnValue:ObjectProperty',GetTimeSeconds='ReturnValue:FloatProperty',PlayMovie='IsLoop:BoolProperty,ReturnValue:BoolProperty',SetMediaSource='InSource:ObjectProperty,bIsPlayOnOpen:BoolProperty',
 SetViewTargetWithBlend='NewViewTarget:ObjectProperty,BlendTime:FloatProperty,BlendFunc:ByteProperty,BlendExp:FloatProperty,bLockOutgoing:BoolProperty',
 PlayNotRegisteredSequence='WorldContextObject:ObjectProperty,SequenceAssetPath:StrProperty,Options:StructProperty,PlaybackSettings:StructProperty,OnFinished:DelegateProperty,ReturnValue:BoolProperty'}
function fn(method)
 return {IsValid=yes,ForEachProperty=function(_,callback)
  local spec=SPECS[method];if BAD_SIGNATURE then spec='Wrong:IntProperty'end
  for key,kind in spec:gmatch('([%w_]+):([%w_]+)')do
   local k,t=key,kind;callback({GetStruct=function()return {GetFullName=function()return BAD_TIMESPAN and 'ScriptStruct Wrong'or'ScriptStruct /Script/CoreUObject.Timespan'end}end,GetFName=function()return n(k)end,GetClass=function()return {GetFName=function()return n(t)end}end})
  end
 end}
end
SEQ_ASSET=asset('/Game/Cinematics/Intro.Intro')
DATA=asset('/Game/Cinematics/Options.Options');DATA.GetClass=function()return {ForEachProperty=function(_,cb)
 cb({GetFName=function()return n('Options')end,GetClass=function()return {GetFName=function()return n('StructProperty')end}end,
 GetStruct=function()return {GetFullName=function()return 'ScriptStruct /Script/LiveCinematics.LiveCinematicsSequenceOptions'end}end})
end}end;DATA.Options={PlayRate=1,StartTime=0,RequiredSubLevels={'actual local native options'}}
function qt(v)return {Time={FrameNumber={Value=v},SubFrame=0},Rate={Numerator=30,Denominator=1}}end
Q={IsValid=yes,GetAddress=function()return 22 end,GetWorld=function()return WORLD end,GetSequence=function()return SEQ_ASSET end,
 GetCurrentTime=function()return qt(FRAME or 0)end,GetStartTime=function()return qt(0)end,GetEndTime=function()return qt(300)end,
 GetActiveCameraComponent=function()return CAM_PRESENT~=false and CAM or nil end,Pause=function()PAUSED=true end,IsPaused=function()return PAUSED end,
 IsPlaying=function()return ISPLAYING end,Play=function()PLAYS=PLAYS+1 end,GoToEndAndStop=function()STOPS=STOPS+1 end,Stop=function()CLOSES=CLOSES+1 end}
LIB={IsValid=yes,GetTotalSeconds=function(_,t)return t.opaque_seconds end,Create=function(_,pc,cls)if cls==SURFACE_CLASS then return SURFACE end;return VIEWER end,PlayNotRegisteredSequence=function(_,world,path,options,settings,delegate)
 SETTINGS=settings;LOCAL_OPTIONS=options;CALLBACK=delegate;SEQ_NEW=true;return true
end}
API={player=function()return PC end,construct=function(cls)if cls==TEXT_CLASS then return LABEL end;return VIEWER end,
 find=function(kind)if kind=='LiveMenuMainTopWidget'then return {MAIN}elseif kind=='LiveManaMovieViewer'then return DISCOVER_MOVIE and{VIEWER}or{}elseif kind=='LiveCinematicsLevelSequencePlayer'then return SEQ_NEW and{Q}or{}end;return {}end,
 static=function(path)
  local method=path:match(':([^:]+)$');if method and SPECS[method]then return fn(method)end
  if path:find('EManaPlayerTrack',1,true)then return ENUM end
  if path=='/Script/UMG.TextBlock'then return TEXT_CLASS end
  if path:find('Default__',1,true)then return LIB end
  return CLASS
 end,
 load=function(path)if path==SURFACE_CLASS:GetFullName():match('^[^ ]+ (.+)$')then return SURFACE_CLASS elseif path=='/Game/Movies/Briefing.Briefing'then return MEDIA elseif path=='/Game/UI/Movie.Movie_C'then return CLASS elseif path=='/Game/Cinematics/Intro.Intro'then return SEQ_ASSET elseif path=='/Game/Cinematics/Options.Options'then return DATA end end}
FName=function(s)return s end
FText=function(s)return s end
C={role='guest'}
DESC={kind=1,asset='/Game/Movies/Briefing.Briefing',viewer='/Game/UI/Movie.Movie_C',options='',duration_ms=10000}
H={object=VIEWER,descriptor=DESC}
'''
class CinemaNativeTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.execute(FIXTURE)
  self.l.globals().M=self.l.execute(SOURCE.read_text(encoding='utf-8'));self.l.execute("E=M.new(C,'source',function()end,API)")
 def test_preparing_decoder_is_not_ready(self):self.l.execute('PREPARING=true;assert(not E.sample(H).ready)')
 def test_no_picture_cannot_ack(self):self.l.execute('VIEWER.ManaTexture=nil;assert(not E.sample(H).ready)')
 def test_audio_track_must_be_selected(self):self.l.execute('SELECTED_AUDIO=-1;assert(not E.sample(H).ready);SELECTED_AUDIO=0;assert(E.sample(H).ready)')
 def test_silent_assets_do_not_require_nonexistent_audio(self):self.l.execute('AUDIOS=0;SELECTED_AUDIO=-1;assert(E.sample(H).ready)')
 def test_native_decode_error_is_not_readiness(self):self.l.execute('ERR=true;assert(not pcall(E.sample,H))')
 def test_pause_must_stop_native_playback(self):self.l.execute('FAIL_PAUSE=true;PAUSED=false;ISPLAYING=true;assert(not pcall(E.pause,H))')
 def test_movie_is_prepared_without_autoplay_and_uses_native_audio_player(self):
  self.l.execute('H=E.open(DESC);assert(AUTO==false and OPEN_SOURCE==MEDIA and E.sample(H).ready and MOUNTED);E.play(H);assert(PLAYS==1)')
 def test_host_skip_does_not_stop_stock_player_directly(self):self.l.execute('E.skip(H,false);assert(STOPS==0);E.skip(H,true);assert(STOPS==1)')
 def test_closing_guest_restores_view_and_removes_own_movie_only(self):self.l.execute('H=E.open(DESC);E.close(H,true);assert(CLOSES==1 and REMOVED and SURFACE_REMOVED and RESTORED)')
 def test_signature_drift_prevents_creation(self):self.l.execute('BAD_SIGNATURE=true;assert(not pcall(E.open,DESC));assert(not OPEN_SOURCE)')
 def test_sequence_uses_live_factory_and_local_environment_with_no_campaign_delegate(self):
  self.l.execute("D={kind=2,asset='/Game/Cinematics/Intro.Intro',options='/Game/Cinematics/Options.Options',viewer='',duration_ms=10000};H=E.open(D);assert(SETTINGS.bDisableGameProcess and SETTINGS.bSkipDisabledOverride and CALLBACK==nil and LOCAL_OPTIONS==DATA.Options);assert(E.sample(H).ready)")
 def test_sequence_camera_must_be_real(self):
  self.l.execute('H={object=Q,descriptor={kind=2,duration_ms=10000}};CAM_PRESENT=false;assert(not E.sample(H).ready);CAM_PRESENT=true;FRAME=297;assert(E.sample(H).ready and E.sample(H).remaining_ms<101)')
 def test_unknown_sequence_options_never_get_replaced_by_empty_defaults(self):
  self.l.execute('SEQ_NEW=true;ISPLAYING=true;assert(not pcall(E.discover))')
 def test_reflected_native_movie_viewer_class_is_a_valid_local_class(self):
  self.l.execute("CLASS.GetFullName=function()return 'Class /Script/Live.LiveManaMovieViewer'end;DISCOVER_MOVIE=true;local h=E.discover();assert(h.descriptor.viewer=='/Script/Live.LiveManaMovieViewer');local guest=E.open(h.descriptor);assert(guest.object==VIEWER)")
 def test_hidden_parent_movie_is_not_a_current_cutscene(self):
  self.l.execute('DISCOVER_MOVIE=true;PARENT={IsValid=yes,IsA=yes,IsVisible=function()return false end};assert(not E.discover())')
 def test_detached_cached_menu_movie_is_not_current(self):
  self.l.execute('DISCOVER_MOVIE=true;VISIBLE=false;assert(not E.discover())')
 def test_native_player_allocation_is_asynchronous(self):
  self.l.execute('VIEWER.GetManaPlayer=function()return nil end;assert(not E.sample(H).ready)')
 def test_another_native_movie_cannot_ack_this_resource(self):
  self.l.execute("VIEWER.PlayingManaSource=asset('/Game/Movies/Other.Other');assert(not E.sample(H).ready)")
 def test_same_path_with_incompatible_local_media_is_blocked(self):
  self.l.execute('PLAYER.GetDuration=function()return {opaque_seconds=12}end;assert(not pcall(E.sample,H))')
 def test_shared_skip_never_calls_destroyed_guest_player(self):
  self.l.execute("VIEWER.IsValid=function()return false end;assert(not pcall(E.skip,H,true));assert(STOPS==0)")
 def test_nested_engine_stage_preserves_native_adapter_behavior(self):
  self.l.execute("STAGES={};C.engine_call=function(name,fn,...)STAGES[#STAGES+1]=name;return fn(...)end;E=M.new(C,'source',function()end,API);H=E.open(DESC);assert(E.sample(H).ready);E.play(H);assert(STAGES[1]=='cinema.open'and STAGES[2]=='cinema.sample'and STAGES[3]=='cinema.play'and PLAYS==1)")
 def test_opaque_timespan_has_no_ticks_member(self):
  self.l.execute("PLAYER.GetDuration=function()return setmetatable({opaque_seconds=10},{__index=function()error('Opaque struct; do not read Ticks')end})end;assert(E.sample(H).ready)")
 def test_zero_metadata_waits_without_descriptor_then_recovers(self):
  self.l.execute('DISCOVER_MOVIE=true;DURATION=0;ISPLAYING=true;PAUSED=false;assert(not E.discover());assert(PAUSED);DURATION=10;local h=E.discover();assert(h.descriptor.duration_ms==10000)')
 def test_guest_zero_metadata_cannot_ack(self):
  self.l.execute('DURATION=0;assert(not E.sample(H).ready);DURATION=10;assert(E.sample(H).ready);DURATION=0;assert(not pcall(E.sample,H))')
 def test_invalid_metadata_is_not_coerced_or_guessed(self):
  for value in ['-1','0/0','math.huge','3601','0.1',"'10'"]:
   self.l.execute(f"DURATION={value};assert(not pcall(E.sample,H))")
 def test_timespan_struct_type_checked_before_call(self):
  self.l.execute("BAD_TIMESPAN=true;LIB.GetTotalSeconds=function()error('must not call')end;local ok,why=pcall(E.sample,H);assert(not ok and tostring(why):find('Changed Timespan conversion input'))")
if __name__=='__main__':unittest.main()
