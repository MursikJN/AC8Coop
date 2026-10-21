// One-way handoff after the separately verified, reversible detachment trial.
// Never reconstruct an AI weak reference after DestroyActor has begun.
bool role_detached_graph(){
 Backend b;if(!same_header(role_unit,true)||!same_header(role_detach.manager,true)||!b.finished_graph()||!role_health.installed||!role_health.forwarded_only)return false;
 uintptr_t vt=0;if(!read(role_unit.pointer+0x298,vt)||vt!=reinterpret_cast<uintptr_t>(role_health_table.data()))return false;
 for(const auto&a:role_detach.unit_arrays){RoleWeakArray now;if(!role_array_capture(a.address,now)||now.count)return false;}
 for(const auto&a:role_detach.manager_arrays){RoleWeakArray now;if(!role_array_capture(a.address,now)||now.count!=a.count-1)return false;
  unsigned next=0;for(int i=0;i<a.count;++i)if(unsigned(i)!=a.remove){if(now.values[next++]!=a.values[i])return false;}
 }
 return verify_baseline(baseline,false);
}
void role_commit_report(const char* reason){
 const auto path=directory+L"\\guest-role-commit-"+AC8_GUEST_REV_W+L".tsv";FILE*f=nullptr;if(_wfopen_s(&f,path.c_str(),L"wb")||!f)return;
 std::fprintf(f,"reason\t%s\nnpc_destroy_entered\t%d\nnpc_retired_verified\t%d\nunit_preserved\t%d\nunit_interface_installed\t%d\nplayer_visible_active\t%d\nplayer_updates_fenced\t%d\nreal_guest_input_authorized\t0\nall_story_commands_bridged\t0\nworld\t0x%llx\nunit\t0x%llx\nunit_index\t%d\nunit_serial\t%d\nold_npc\t0x%llx\nold_npc_index\t%d\nold_npc_serial\t%d\nplayer\t0x%llx\nplayer_index\t%d\nplayer_serial\t%d\n",reason,role_destroy_entered?1:0,role_npc_retired?1:0,same_header(role_unit,true)?1:0,role_health.installed?1:0,role_display_active?1:0,Backend{}.finished_graph()?1:0,static_cast<unsigned long long>(baseline.world),static_cast<unsigned long long>(role_unit.pointer),role_unit.index,role_unit.serial,static_cast<unsigned long long>(role_npc.pointer),role_npc.index,role_npc.serial,static_cast<unsigned long long>(ledger.raw_owned),ledger.owned.index,ledger.owned.serial);
 std::fclose(f);
}
bool role_reseed_at_slot(){
 Backend b;ObservationReader reader;observation::Actor npc;
 if(!observation::capture_actor(reader,role_npc.pointer,npc)||!npc.root.transform_valid||!b.stage_current())return diagnostic_fail("replacement_initial_pose_unverified");
 for(unsigned i=0;i<3;++i){
  if(!std::isfinite(baseline.pose[i])||std::fabs(baseline.pose[i]-npc.root.world[i])>2||baseline.pose[i]<INT32_MIN||baseline.pose[i]>INT32_MAX)return diagnostic_fail("replacement_request_not_at_baxter");
  plane_initial_state::put(snapshot.main,0x2c+i*4,static_cast<int32_t>(std::llround(baseline.pose[i])));
  plane_initial_state::put(snapshot.main,0x38+i*4,static_cast<float>(baseline.pose[i+3]));
 }
 for(unsigned i=0;i<6;++i)plane_initial_state::put(snapshot.aux170,8+i*4,0.0f);
 plane_initial_state::put(snapshot.aux170,0x20,uint8_t{0});auto c=b.caches();plane_initial_state::Result result;
 if(!plane_initial_state::stage(b,snapshot,c,result)||!plane_flight_state::finalize(b,snapshot,c,model_report)||!b.pose_and_final_barrier())return diagnostic_fail("replacement_slot_model_initialization_failed");
 observation::Actor owned;
 if(!observation::capture_actor(reader,ledger.raw_owned,owned)||!owned.root.transform_valid)return false;
 for(unsigned i=0;i<3;++i)if(std::fabs(owned.root.world[i]-npc.root.world[i])>2)return diagnostic_fail("replacement_slot_pose_readback_failed");
 return true;
}
bool role_retire_npc(){
 if(role_destroy_entered)return diagnostic_fail("npc_retirement_already_entered");
 std::string armed;if(!read_file(L"role-retire-armed.txt",armed))return diagnostic_fail("retirement_not_armed");
 while(!armed.empty()&&(armed.back()=='\r'||armed.back()=='\n'))armed.pop_back();
 if(armed!=ready_stamp||GetTickCount64()-ready_tick>10000||!role_prepared||!role_health.consumed||!same_header(role_npc,true)||!role_reseed_at_slot())return diagnostic_fail("retirement_preparation_stale_or_invalid");
 if(!role_detach_apply()||!role_detached_graph()){
  const bool restored=role_detach_restore()&&role_health_restore();
  return diagnostic_fail(restored?"retirement_detachment_refused_and_restored":"retirement_detachment_quarantined");
 }
 // All groups are detached and the role's health/UI routes target the player.
 // At this point the existing NPC may be retired exactly once.
 role_destroy_entered=true;role_commit_report("npc_destroy_enter");event("role_npc_destroy_enter");
 using Destroy=bool(__fastcall*)(uintptr_t,bool);const bool accepted=reinterpret_cast<Destroy>(image_base+destroy_rva)(role_npc.pointer,false);event(accepted?"role_npc_destroy_return_true":"role_npc_destroy_return_false");
 if(!accepted){uint8_t state=0;uint32_t flags=0;
  if(same_header(role_npc,true)&&read(role_npc.pointer+0x5d,state)&&read(role_npc.pointer+8,flags)&&!(state&1)&&!(flags&0x40000000)){
   role_destroy_entered=false;const bool restored=role_detach_restore()&&role_health_restore();
   native_failure=restored?"npc_destroy_refused_role_restored":"npc_destroy_refused_restore_unverified";role_commit_report(native_failure);return false;
  }
 }
 native_failure="npc_destroy_requested_retirement_pending";role_commit_report(native_failure);return true;
}
bool role_poll_retirement(){
 if(!role_destroy_entered)return diagnostic_fail("npc_retirement_not_entered");
 Backend b;const plane_flight::Identity old{role_npc.pointer,role_npc.index,role_npc.serial};
 role_npc_retired=b.resolve(old)==plane_flight::Seen::retired;
 if(!role_detached_graph()){native_failure="replacement_role_graph_changed";role_commit_report(native_failure);return false;}
 native_failure=role_npc_retired?"npc_retired_unit_preserved_player_reserved":"npc_retirement_pending";role_commit_report(native_failure);return role_npc_retired;
}
bool role_visual_prepare(){
 if(!role_npc_retired||!role_destroy_entered||role_display_active||!role_detached_graph())return diagnostic_fail("visual_replacement_not_ready");
 Backend b;if(!b.enable_main_visibility()||!b.pose_and_final_barrier())return false;
 role_activation_pending=true;native_failure="replacement_visibility_prepared_stock_activation_pending";role_commit_report(native_failure);return true;
}
bool role_visual_finish(){
 if(!role_activation_pending||!role_npc_retired||!role_destroy_entered)return diagnostic_fail("replacement_activation_not_armed");
 Backend b;uint8_t active=0;if(!b.own_actor()||!read(ledger.raw_owned+0x3f4,active)||active!=1)return diagnostic_fail("stock_player_activation_not_observed");
 role_display_active=true;b.close_actor_barrier();
 if(!b.disable_components()||!b.finished_graph()||!role_detached_graph())return diagnostic_fail("replacement_activation_barrier_unverified");
 role_activation_pending=false;native_failure="four_plane_role_replacement_visual_ready_input_unbound";role_commit_report(native_failure);return true;
}
