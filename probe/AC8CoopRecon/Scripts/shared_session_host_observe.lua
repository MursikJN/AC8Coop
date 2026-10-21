return function(output)
 assert(os.getenv('AC8_COOP_RECON')=='1')
 local task=assert(os.getenv('AC8_COOP_RECON_EXTENSION'))
 local directory=assert(task:match('^(.*)[/\\][^/\\]+$'))
 assert(loadfile(directory..'/shared_session_connection_observer.lua'))()(output,'host')
end
