"""Single-game loopback proof. This simulates a peer, never claims a real guest."""
import argparse,json,math,socket,struct,time
from pathlib import Path
SIZE=368
def fields(path):return dict(line.split('\t',1)for line in path.read_text(encoding='utf-8-sig').splitlines()if '\t'in line)
def packet(kind,token,sequence,generation,revision,roll=0):
 b=bytearray(SIZE);struct.pack_into('<4sHHII6Q6I5h',b,0,b'AC8P',1,SIZE,25201480,kind,2,token,token,sequence,generation,0,revision,7,1,23,0,0,0,roll,0,0,0);return b
def decode(b):
 assert len(b)==SIZE;head=struct.unpack_from('<4sHHII6Q6I',b);assert head[:4]==(b'AC8P',1,SIZE,25201480)and head[4]==1
 poses=[struct.unpack_from('<II3d4f3fI',b,104+64*i)for i in range(4)]
 assert all(all(math.isfinite(v)for v in p[2:12])for p in poses)
 return {'sequence':head[8],'generation':head[9],'revision':head[11],'guest_position':poses[1][2:5],'guest_quaternion':poses[1][5:9]}
def run(output):
 deadline=time.monotonic()+20
 while True:
  try:s=fields(output/'guest-pilot-status.tsv')
  except(OSError,ValueError):s={}
  if s.get('active')=='1'and int(s.get('port','0')):break
  if time.monotonic()>deadline:raise TimeoutError('Host pilot bridge did not start')
  time.sleep(.02)
 token=int(s['local_test_token']);generation=int(s['generation']);revision=int(s['configuration_revision'])
 frames=[];buffer=bytearray();seq=1
 with socket.create_connection(('127.0.0.1',int(s['port'])),timeout=1)as stream:
  stream.setblocking(False);stream.sendall(packet(2,token,seq,generation,revision));seq+=1
  start=time.monotonic();next_send=start
  while time.monotonic()-start<2.2:
   now=time.monotonic();elapsed=now-start
   if now>=next_send:
    stream.sendall(packet(3,token,seq,generation,revision,16384 if .6<=elapsed<1.6 else 0));seq+=1;next_send=now+1/60
   try:
    data=stream.recv(65536)
    if not data:break
    buffer.extend(data)
   except BlockingIOError:pass
   while len(buffer)>=SIZE:
    b=bytes(buffer[:SIZE]);del buffer[:SIZE];frames.append(decode(b))
   time.sleep(.002)
  stream.sendall(packet(4,token,seq,generation,revision))
 assert len(frames)>10,'Need advancing authoritative state frames'
 first=frames[0]['guest_quaternion'];max_delta=max(min(math.sqrt(sum((a-b)**2 for a,b in zip(first,f['guest_quaternion']))),math.sqrt(sum((a+b)**2 for a,b in zip(first,f['guest_quaternion']))))for f in frames)
 result={'simulated_peer':True,'real_guest_connected':False,'received_frames':len(frames),'orientation_delta':max_delta,'frames':frames}
 (output/'pilot-loopback-proof.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 assert max_delta>.03,'Transport roll did not produce independent orientation response'
 print(json.dumps({k:v for k,v in result.items()if k!='frames'}))
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);run(p.parse_args().output)
