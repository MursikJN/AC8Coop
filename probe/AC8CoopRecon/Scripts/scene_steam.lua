-- Independent replication channel. Lobby, input and scene-ready acknowledgments
-- remain separate; receiving a scene never grants aircraft control.
local M={}
function M.start()
 assert(os.getenv('AC8_SCENE_STEAM')=='25201480','Scene Steam profile required')
 local dll=assert(os.getenv('AC8_SCENE_DLL'),'Scene DLL path required')
 local start=assert(package.loadlib(dll,'luaopen_ac8_scene_start'))
 local tick=assert(package.loadlib(dll,'luaopen_ac8_scene_tick'))
 local stop=assert(package.loadlib(dll,'luaopen_ac8_scene_stop'))
 start();return{update=tick,stop=stop}
end
return M
