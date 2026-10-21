-- Observe only the peer's existing legacy P2P session; never dispatch or accept it.
return function(output,read_state)
 assert(not _G.AC8NativeLegacyObserver,'Legacy observer already running')
 local previous;local changes=0
 local function tick()
  read_state()
  local f=assert(io.open(output..'/native-steam-state.tsv','r'));local text=f:read(4097);f:close();assert(#text<=4096,'State budget')
  text=text:gsub('observed_tick_ms\t%d+\n','')
  if text~=previous then
   changes=changes+1;f=assert(io.open(output..'/native-steam-state-events.tsv','a'));f:write(os.time(),'\t',text:gsub('\n',' | '),'\n');f:close();previous=text
  end
  if changes<4096 then ExecuteInGameThreadWithDelay(1000,_G.AC8NativeLegacyObserver)end
 end
 _G.AC8NativeLegacyObserver=tick;tick()
end
