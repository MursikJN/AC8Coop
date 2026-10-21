import importlib.util
import math
from pathlib import Path
import socket
import struct
import uuid
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('scene_viewer', ROOT / 'coop/scene_viewer.py')
viewer = importlib.util.module_from_spec(spec); spec.loader.exec_module(viewer)


def frame(sequence=1, generation=1, stage=0, x=0, ids=(1, 2), events=None, complete=True):
    return dict(sequence=sequence, generation=generation, revision=1, source_ms=sequence*200,
                world='/Game/Maps/Mission007', complete=complete, paused=True,
                session=dict(epoch=1, stage=stage, mission=6, difficulty=1, ready=3, loaded=0,
                             votes=0, scene=1, host_aircraft=7, guest_aircraft=23, observed='test_fixture'),
                entities=[dict(id=i, kind='plane', role=i-1, alive=True, health=2060,
                               asset='/Game/Test/Plane', label='Тестовый самолёт '+str(i),
                               position=[x, i*1000, 10000], rotation=[0, 0, 0, 1]) for i in ids],
                events=events or [], event_cursor=(events[-1]['id'] if events else 0))


class SceneTests(unittest.TestCase):
    def setUp(self): self.replica = viewer.Replica()
    def wire(self, f):
        return self.replica.codec.encode(self.replica.lua.table_from(f, recursive=True)).encode('utf-8')

    def test_roundtrip_unicode_and_unknown_health(self):
        f=frame(); f['entities'][0]['health']=False
        self.assertTrue(self.replica.accept(self.wire(f), 100)[0]); self.replica.render(100)
        self.assertFalse(self.replica.entities[1]['health'])
        self.assertIn('Тестовый', self.replica.entities[1]['label'])

    def test_generation_rebuild_and_authoritative_despawn(self):
        self.replica.accept(self.wire(frame()), 100)
        self.replica.accept(self.wire(frame(2, ids=(2,))), 300)
        self.assertEqual(set(self.replica.entities), {2})
        self.replica.accept(self.wire(frame(1, 2, ids=(1,))), 500)
        self.assertEqual(set(self.replica.entities), {1})
        self.assertEqual(self.replica.removed, 2)

    def test_incomplete_snapshot_cannot_delete_replicas(self):
        self.replica.accept(self.wire(frame()), 100)
        accepted, reason=self.replica.accept(self.wire(frame(2, ids=(), complete=False)), 200)
        self.assertFalse(accepted); self.assertEqual(reason, 'incomplete_inventory')
        self.assertEqual(set(self.replica.entities), {1,2})

    def test_malformed_frame_has_no_partial_effect(self):
        self.replica.accept(self.wire(frame()), 100)
        with self.assertRaises(Exception): self.replica.accept(self.wire(frame(2, ids=(2,)))[:-5], 200)
        self.assertEqual(set(self.replica.entities), {1,2}); self.assertEqual(self.replica.core.sequence, 1)

    def test_replay_and_old_world_rejected(self):
        self.replica.accept(self.wire(frame(2, 2)), 100)
        self.assertFalse(self.replica.accept(self.wire(frame(1, 1)), 200)[0])
        self.assertFalse(self.replica.accept(self.wire(frame(2, 2)), 200)[0])

    def test_event_deduplication_and_gap(self):
        events=[dict(id=1,kind='health',entity=2,detail='2000'),dict(id=2,kind='death',entity=2,detail='dead')]
        self.replica.accept(self.wire(frame(events=events)), 100)
        self.replica.accept(self.wire(frame(2, events=events)), 300)
        self.assertEqual(self.replica.core.events_applied,2)
        gap=[dict(id=5,kind='result',entity=0,detail='test')]
        self.assertEqual(self.replica.accept(self.wire(frame(3,events=gap)), 500),(False,'event_gap'))
        self.assertEqual(self.replica.core.sequence,2)
        self.assertTrue(self.replica.accept(self.wire(frame(3,events=gap)), 500,baseline=True)[0])

    def test_noncontiguous_events_rejected_before_world_change(self):
        events=[dict(id=1,kind='spawn',entity=2,detail=''),dict(id=3,kind='death',entity=2,detail='')]
        with self.assertRaises(Exception):self.replica.accept(self.wire(frame(events=events)),100)
        self.assertEqual(self.replica.created,0)

    def test_interpolation_and_stale_controls(self):
        self.replica.accept(self.wire(frame(x=0)),100)
        self.replica.accept(self.wire(frame(2,x=200)),300)
        self.replica.render(300)
        self.assertAlmostEqual(self.replica.entities[1]['position'][0],100)
        self.assertTrue(self.replica.core.view()['can_ready'])
        self.assertFalse(self.replica.render(801)[0]); self.assertFalse(self.replica.core.view()['can_ready'])

    def test_guest_menu_waits_for_host_and_never_starts(self):
        for stage in range(9):
            self.replica.accept(self.wire(frame(stage+1,stage=stage)),stage*200)
            v=self.replica.core.view()
            self.assertFalse(v['can_select_mission']); self.assertFalse(v['can_start'])
            self.assertEqual(v['can_ready'],stage in (0,4)); self.assertEqual(v['can_vote'],stage==2)

    def test_invalid_entity_id_or_quaternion_rejected(self):
        for mutation in ('id','quaternion','nan'):
            f=frame()
            if mutation=='id': f['entities'][1]['id']=1
            elif mutation=='quaternion': f['entities'][0]['rotation']=[0,0,0,0]
            else: f['entities'][0]['position'][0]=math.nan
            with self.assertRaises(Exception): self.wire(f)

    def test_real_socket_transfers_data_to_same_client_core(self):
        folder=ROOT/'build'/('scene-wire-test-'+uuid.uuid4().hex)
        host=folder/'host'; host.mkdir(parents=True); client=folder/'client'
        link=viewer.LocalLink(host,client)
        try:
            link.start()
            for seq in (1,2,3):
                (host/'scene-host.ac8w').write_bytes(self.wire(frame(seq,x=seq*100)))
                data=link.incoming.get(timeout=2)
                self.assertTrue(self.replica.accept(data,seq*200)[0])
            self.replica.render(600)
            self.assertEqual(self.replica.core.sequence,3)
            self.assertEqual(link.received,3)
        finally: link.close()

    def test_svg_escapes_labels(self):
        f=frame(); f['entities'][0]['label']='<script>&'
        self.replica.accept(self.wire(f),100); self.replica.render(100)
        image=viewer.svg(self.replica.snapshot())
        self.assertIn('&lt;script&gt;&amp;',image); self.assertNotIn('<script>',image)

    def visual_frame(self):
        f=frame();f['visual_complete']=True
        f['visuals']=[dict(entity=1,slot=1,kind='skeletal',asset='/Game/Meshes/Test.Test',
                           position=[10,20,30],rotation=[0,0,0,1],scale=[1,1,1],
                           materials=['/Game/Materials/Test.Test',''])]
        return f

    def test_visual_catalog_roundtrip_keeps_material_slots(self):
        payload=self.wire(self.visual_frame());self.assertTrue(payload.startswith(b'AC8W\t2\t'))
        decoded=self.replica.codec.decode(payload.decode('utf-8'))
        self.assertEqual(decoded['visuals'][1]['materials'][2],'')
        self.assertEqual(decoded['visuals'][1]['position'][3],30)
        self.assertTrue(self.replica.accept(payload,100)[0])

    def test_unknown_visual_owner_or_external_asset_rejected(self):
        for field,value in [('entity',999),('asset','C:/Windows/test.dll'),('slot',0)]:
            f=self.visual_frame();f['visuals'][0][field]=value
            with self.assertRaises(Exception):self.wire(f)

    def test_duplicate_visual_slot_and_truncated_catalog_rejected(self):
        f=self.visual_frame();f['visuals'].append(dict(f['visuals'][0]))
        with self.assertRaises(Exception):self.wire(f)
        payload=self.wire(self.visual_frame()).replace(b'end\t1\t2\t0\t1',b'end\t1\t2\t0\t2')
        with self.assertRaises(Exception):self.replica.accept(payload,100)

    def test_asset_preflight_failure_preserves_existing_scene(self):
        self.replica.accept(self.wire(frame()),100)
        self.replica.lua.globals().scene=self.replica.core
        self.replica.lua.execute("scene.reset('test')")
        lua=self.replica.lua;lua.globals().codec=self.replica.codec
        module=lua.execute((viewer.SCRIPTS/'scene_client.lua').read_text())
        lua.globals().module=module
        lua.execute("removed=0;made=0;adapter={remove=function()removed=removed+1 end,create=function()made=made+1 end,event=function()end,menu=function()end,update=function()end};s=module.new(codec,adapter)")
        lua.globals().s.accept(self.wire(frame()).decode(),100,True)
        lua.execute("adapter.prepare=function()error('missing mesh')end")
        with self.assertRaises(Exception):lua.globals().s.accept(self.wire(frame(2,2,ids=(2,))).decode(),200,False)
        self.assertEqual(lua.globals().removed,0);self.assertEqual(lua.globals().made,2)

    def test_relative_component_pose_reconstructs_world(self):
        transform=self.replica.lua.execute((viewer.SCRIPTS/'scene_transform.lua').read_text())
        parent=self.replica.lua.table_from(dict(position=[100,200,300],rotation=[0,0,math.sqrt(.5),math.sqrt(.5)]),recursive=True)
        position=self.replica.lua.table_from([90,205,330]);q=self.replica.lua.table_from([0,0,0,1])
        p,r=transform.relative(parent,position,q)
        out,rotation=transform.world(parent,self.replica.lua.table_from(dict(position=p,rotation=r)))
        for i in range(1,4):self.assertAlmostEqual(out[i],position[i])
        self.assertAlmostEqual(abs(rotation[4]),1)

    def test_scene_clock_uses_engine_wall_time_even_when_cpu_clock_runs_fast(self):
        lua=self.replica.lua;clock=lua.execute((viewer.SCRIPTS/'scene_clock.lua').read_text())
        lua.execute('context={IsValid=function()return true end};g={IsValid=function()return true end,GetRealTimeSeconds=function()return 3.25 end};os.clock=function()return 999999 end')
        self.assertEqual(clock.milliseconds(lua.globals().context,lua.globals().g),3250)

    def test_network_receive_continues_when_display_queue_is_full(self):
        folder=ROOT/'build'/('scene-background-test-'+uuid.uuid4().hex);host=folder/'host';host.mkdir(parents=True)
        link=viewer.LocalLink(host,folder/'client',forward_preview=True)
        try:
            link.start()
            for sequence in range(1,13):
                (host/'scene-host.ac8w').write_bytes(self.wire(frame(sequence)))
                deadline=time.monotonic()+2
                while link.received<sequence:
                    self.assertLess(time.monotonic(),deadline,link.error);time.sleep(.01)
            self.assertGreater(link.display_frames_skipped,0)
            payload=(host/'scene-client-preview.ac8w').read_text(encoding='utf-8')
            self.assertEqual(self.replica.codec.decode(payload)['sequence'],12)
        finally:link.close()

    def test_paused_preview_restores_exact_quality_settings(self):
        lua=self.replica.lua;quality=lua.execute((viewer.SCRIPTS/'scene_preview_quality.lua').read_text())
        lua.execute("values={['r.DepthOfFieldQuality']=3,['r.MotionBlurQuality']=2};library={IsValid=function()return true end,GetConsoleVariableIntValue=function(_,key)return values[key]end,ExecuteConsoleCommand=function(_,world,command,pc)local key,value=command:match('^(%S+) (%d+)$');values[key]=tonumber(value)end}")
        saved=quality.push(None,None,lua.globals().library)
        self.assertEqual(lua.globals()['values']['r.DepthOfFieldQuality'],0)
        saved.restore();self.assertEqual(lua.globals()['values']['r.DepthOfFieldQuality'],3)
        self.assertEqual(lua.globals()['values']['r.MotionBlurQuality'],2)


if __name__=='__main__':unittest.main()
