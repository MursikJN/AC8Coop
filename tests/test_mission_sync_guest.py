import unittest
from coop.mission_sync_guest import SyncGuest

class Client:
    def __init__(self):
        self.connected=True;self.pending=None;self.commands=[];self.events=[]
        self.snapshot=dict(phase='1',epoch='2',revision='3',loaded_mask='1',commit_mask='0',release_at='0',scene='1',vote_mask='0')
    def command(self,*args):self.commands.append(args);self.pending=True
    def log(self,*args):self.events.append(args)

class SyncGuestTests(unittest.TestCase):
    def setUp(self):
        self.tick=100;self.client=Client();self.guest=SyncGuest(self.client,lambda:self.tick)
    def test_delayed_loading_only_acknowledges_current_world(self):
        self.guest.set_delay(1,8000);self.guest.update();self.tick=8099;self.guest.update()
        self.assertEqual(self.client.commands,[])
        self.tick=8100;self.guest.update();self.assertEqual(self.client.commands[0][0],7)
        self.client.pending=None;self.client.snapshot['loaded_mask']='3';self.guest.update()
        self.assertEqual(len(self.client.commands),1)
        self.client.snapshot.update(phase='5',epoch='8',loaded_mask='1')
        self.guest.update();self.assertEqual(len(self.client.commands),1)
        self.tick+=10000;self.guest.update();self.assertEqual(len(self.client.commands),2)
    def test_rearm_discards_old_commit_schedule(self):
        self.guest.set_delay('commit',1000);self.client.snapshot.update(loaded_mask='3',release_at='2000')
        self.guest.update();self.tick=500;self.client.snapshot['release_at']='3500';self.guest.update()
        self.tick=1100;self.guest.update();self.assertEqual(self.client.commands,[])
        self.tick=1500;self.guest.update();self.assertEqual(self.client.commands[0][1],3500)
    def test_duplicate_vote_uses_original_epoch_and_revision(self):
        self.client.snapshot['phase']='2';self.guest.vote();self.client.pending=None
        self.client.snapshot.update(epoch='9',revision='10',scene='2');self.guest.repeat_last()
        self.assertEqual(self.client.commands[0][:2]+self.client.commands[0][3:],self.client.commands[1][:2]+self.client.commands[1][3:])
        self.assertEqual(self.client.commands[1][4],('2','3'))
    def test_continuous_hold_never_votes_twice_or_on_next_scene(self):
        self.client.snapshot['phase']='2';self.guest.hold(True,1000)
        self.tick=1099;self.guest.hold(True,1000);self.assertEqual(self.client.commands,[])
        self.tick=1100;self.guest.hold(True,1000);self.assertEqual(len(self.client.commands),1)
        self.client.pending=None;self.client.snapshot.update(scene='2',epoch='3')
        self.tick=10000;self.guest.hold(True,1000);self.assertEqual(len(self.client.commands),1)
        self.guest.hold(False,1000);self.guest.hold(True,1000);self.tick+=1000;self.guest.hold(True,1000)
        self.assertEqual(len(self.client.commands),2)
    def test_hold_outside_scene_does_not_carry_into_scene(self):
        self.guest.hold(True,1000);self.tick=5000;self.client.snapshot['phase']='2';self.guest.hold(True,1000)
        self.assertEqual(self.client.commands,[])
    def test_release_is_logged_once(self):
        self.client.snapshot.update(loaded_mask='3',release_at='2000',commit_mask='3')
        self.tick=2003;self.guest.update();self.guest.update()
        self.assertEqual(sum(e[0]=='simulator_release'for e in self.client.events),1)
        self.assertIn('lateness_ms=3',self.client.events[-1][1])

if __name__=='__main__':unittest.main()
