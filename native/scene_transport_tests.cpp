#define AC8_SCENE_TRANSPORT
#define main original_connection_regression
#include "connection_runtime_tests.cpp"
#undef main
static unsigned checks=0;
static void verify(bool value){++checks;if(!value){printf("scene FAIL %u\n",checks);exit(1);}}
struct SceneMessage:SteamNetworkingMessage_t{
 std::vector<uint8_t>bytes;
 explicit SceneMessage(const ac8scene::Chunk&f){bytes=ac8scene::encode(f);m_pData=bytes.data();m_cbSize=int(bytes.size());m_conn=connection;m_identityPeer.Clear();m_identityPeer.SetSteamID64(peer_id);m_pfnRelease=[](SteamNetworkingMessage_t*p){++freed_messages;delete static_cast<SceneMessage*>(p);};}
};
static ac8scene::Chunk sample(){ac8scene::Chunk f;f.sender=1;f.session=2;f.echo=3;f.sequence=1;f.generation=1;f.transfer=1;f.total=20000;f.count=2;f.data=std::string(ac8scene::chunk_size,'a');return f;}
static std::vector<std::vector<uint8_t>> sent_scene;
static EResult capture_send(void*,HSteamNetConnection,const void*data,uint32 size,int,int64*){
 ac8scene::Chunk f;if(ac8scene::decode(data,size,f))sent_scene.emplace_back(static_cast<const uint8_t*>(data),static_cast<const uint8_t*>(data)+size);return k_EResultOK;
}
int main(){
 original_connection_regression();auto f=sample();ac8scene::Chunk decoded;auto wire=ac8scene::encode(f);verify(ac8scene::decode(wire.data(),wire.size(),decoded));verify(decoded.data==f.data);
 for(size_t at:{size_t(4),size_t(6),size_t(8),size_t(12),size_t(64),size_t(68),size_t(72),size_t(76)}){auto bad=wire;if(at==76)ac8test::put(bad.data()+at,0,4);else bad[at]^=0xff;verify(!ac8scene::decode(bad.data(),bad.size(),decoded));}
 ac8scene::Assembler a;std::string out;verify(a.accept(f,out)&&out.empty());auto last=f;last.index=1;last.sequence=2;last.data=std::string(f.total-ac8scene::chunk_size,'b');verify(a.accept(last,out)&&out.size()==20000&&out.back()=='b');verify(!a.accept(f,out));
 auto next=f;next.transfer=2;next.sequence=3;verify(a.accept(next,out));verify(!a.accept(next,out));auto wrong=last;wrong.transfer=3;verify(!a.accept(wrong,out));
 next.generation=2;next.transfer=1;verify(a.accept(next,out));last.generation=2;last.transfer=1;verify(a.accept(last,out)&&out.size()==20000);verify(!a.accept(f,out));
 reset_fake();scene_pending.clear();scene_assembler={};scene_rx=scene_tx=0;auto peer=complete_handshake(801);role=Role::guest;action_thread=GetCurrentThreadId();
 f=sample();f.sender=peer_id;f.session=peer.nonce;f.echo=session.nonce;inbound.push_back(new SceneMessage(f));last=f;last.index=1;last.sequence=2;last.data=std::string(f.total-ac8scene::chunk_size,'b');inbound.push_back(new SceneMessage(last));pump();
 verify(ac8scene_transport::take(out)&&out.size()==20000);verify(!ac8scene_transport::take(out));
 auto spoof=last;spoof.sequence=3;spoof.echo++;inbound.push_back(new SceneMessage(spoof));pump();verify(!connection&&scene_pending.empty());
 reset_fake();complete_handshake(802);action_thread=GetCurrentThreadId();api.send=capture_send;sent_scene.clear();std::string source(40000,'x');verify(ac8scene_transport::send(source,1,1));verify(sent_scene.size()==3);
 a={};for(const auto&packet:sent_scene){verify(ac8scene::decode(packet.data(),packet.size(),decoded));verify(decoded.sender==local_id&&decoded.session==session.nonce&&decoded.echo==session.remote);verify(a.accept(decoded,out));}verify(out==source);
 role=Role::guest;verify(!ac8scene_transport::send(source,1,2));
 printf("%u scene framing, assembly, SDK identity and transport checks plus existing regression passed\n",checks);
}
