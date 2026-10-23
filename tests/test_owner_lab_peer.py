"""Real loopback helper exchange, without any game or Steam process."""
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time
import unittest
ROOT=Path(__file__).resolve().parents[1]
EXE=ROOT/'build/steam-coop-r31/owner_lab_peer.exe'
@unittest.skipUnless(EXE.exists(),'Build the R31 lab helper first')
class LabPeerTests(unittest.TestCase):
 def test_cpp_owner_wire_matches_lua_consumer(self):
  from lupa import LuaRuntime
  with tempfile.TemporaryDirectory()as temp:
   fixture=Path(temp)/'owner.ac8p'
   subprocess.run([str(EXE),'--wire-fixture',str(fixture)],check=True,timeout=5,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
   data=fixture.read_bytes();self.assertEqual(data[360:368],bytes(8));self.assertEqual(struct.unpack_from('<ddd',data,368),(101,202,303))
   lua=LuaRuntime(encoding=None);view=lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/guest_pilot_view.lua').read_bytes());frame=view[b'owner'](data)
   self.assertEqual([frame[b'velocity'][i]for i in range(1,4)],[101,202,303])
 def test_loaded_owner_state_and_stop_on_loopback(self):self.exercise()
 def test_slow_preparation_over_old_timeout_never_acknowledges_early(self):self.exercise(wait_before_loaded=16)
 def test_peer_close_writes_terminal_error(self):self.exercise(close_early=True)
 def exercise(self,wait_before_loaded=0,close_early=False):
  with tempfile.TemporaryDirectory()as temp:
   directory=Path(temp);token=456789
   (directory/'owner-lab-host-seed.tsv').write_text('x\t100\ny\t200\nz\t150000\nqx\t0\nqy\t0\nqz\t0\nqw\t1\nspeed\t250\n')
   process=subprocess.Popen([str(EXE),str(directory),str(token)],creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
   try:
    deadline=time.monotonic()+5;port=0
    while time.monotonic()<deadline:
     config=directory/'owner-lab-peer.tsv'
     if config.exists():
      values=dict(line.split('\t')for line in config.read_text().splitlines()if'\t'in line);port=int(values.get('port',0))
      if port:break
     time.sleep(.01)
    self.assertGreater(port,0)
    with socket.create_connection(('127.0.0.1',port),timeout=3)as connection:
     connection.settimeout(3)
     def receive():
      data=b''
      while len(data)<392:
       block=connection.recv(392-len(data));self.assertTrue(block);data+=block
      self.assertEqual(struct.unpack_from('<4sHH',data),(b'AC8P',3,392));return data
     def frame(kind,sequence,owner=False):
      data=bytearray(392);struct.pack_into('<4sHHII6Q6I',data,0,b'AC8P',3,392,25201480,kind,2,token,token,sequence,1,1000 if owner else 0,1,7,1,23,0,1 if owner else 0)
      if owner:struct.pack_into('<IIdddfffffffI',data,104,1,23,100,200,150000,0,0,0,1,250,0,0,0)
      return data
     receive()
     if close_early:
      connection.shutdown(socket.SHUT_RDWR);connection.close();process.wait(timeout=4)
      values=dict(line.split('\t')for line in (directory/'owner-lab-peer-status.tsv').read_text().splitlines())
      self.assertNotEqual(process.returncode,0);self.assertEqual(values['final'],'1');self.assertEqual(values['error'],'peer_closed');return
     until=time.monotonic()+wait_before_loaded
     while time.monotonic()<until:
      self.assertFalse(struct.unpack_from('<I',receive(),80)[0]&8,'Loading grace must not fake loaded acknowledgement')
     connection.sendall(frame(2,1));connection.sendall(frame(5,2,True))
     acknowledged=False
     for _ in range(20):
      if struct.unpack_from('<I',receive(),80)[0]&8:acknowledged=True;break
     self.assertTrue(acknowledged);connection.sendall(frame(4,3));process.wait(timeout=4);self.assertEqual(process.returncode,0)
     values=dict(line.split('\t')for line in (directory/'owner-lab-peer-status.tsv').read_text().splitlines())
     self.assertEqual(values['final'],'1');self.assertEqual(values['error'],'none');self.assertEqual(values['receive_timeout_ms'],'15000')
   finally:
    if process.poll()is None:process.terminate();process.wait(timeout=4)
if __name__=='__main__':unittest.main()
