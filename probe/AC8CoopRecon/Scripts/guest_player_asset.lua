-- Class preparation only. Invoke the consumer immediately on the game thread.
-- A Lua UObject wrapper is not a promise of asset lifetime across later frames.
-- API: https://docs.ue4ss.com/lua-api/global-functions/loadasset.html
local M={}
function M.with_class(resolver,consumer,api)
 api=api or{load=LoadAsset,static=StaticFindObject}
 local before=resolver.resolve()
 if not before.player_class_loaded then assert(type(api.load)=='function','Game-thread asset loader unavailable');api.load(before.player_class_path)end
 local fresh=resolver.verify(before)
 assert(fresh.player_class_loaded,'F-14D player class failed to load')
 local base=api.static('/Script/Live.LivePlayerPlane')
 assert(base and base:IsValid()and fresh.player_class:IsChildOf(base),'Asset does not implement the stock player flight class')
 local cdo=fresh.player_class:GetCDO()
 assert(cdo and cdo:IsValid(),'F-14D player default object unavailable')
 return consumer(fresh,cdo)
end
return M
