"""One-game replica inspector. Draws only frames received through a TCP socket.

The schematic is a debug renderer, not the full game's second client renderer.
Lua scene_client/scene_codec are shared with the UE adapter, without campaign AI.
"""
from __future__ import annotations

import argparse
import ctypes
import html
import json
import math
import os
import queue
import secrets
import socket
import struct
import threading
import time
from pathlib import Path

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'probe/AC8CoopRecon/Scripts'
MAX_BYTES = 2_097_152
STAGES = ('Лобби', 'Загрузка вступления', 'Катсцена', 'Загрузка ангара',
          'Ангар', 'Загрузка полёта', 'Полёт', 'Результат', 'Остановлено')


def plain(value):
    if hasattr(value, 'items'):
        items = dict(value.items())
        if items and set(items) == set(range(1, len(items) + 1)):
            return [plain(items[i]) for i in range(1, len(items) + 1)]
        return {k: plain(v) for k, v in items.items()}
    return value


class Replica:
    """Thread-confined Lua client, with a minimal renderer adapter."""
    def __init__(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.codec = self.lua.execute((SCRIPTS / 'scene_codec.lua').read_text(encoding='utf-8'))
        core = self.lua.execute((SCRIPTS / 'scene_client.lua').read_text(encoding='utf-8'))
        self.entities = {}
        self.events = []
        self.menu = {}
        self.created = self.removed = 0
        adapter = self.lua.table_from(dict(create=self.create, remove=self.remove,
                                          update=self.update, event=self.event, menu=self.set_menu))
        self.core = core.new(self.codec, adapter)

    def create(self, entity):
        entity = plain(entity)
        self.entities[entity['id']] = entity
        self.created += 1

    def remove(self, entity_id, _reason):
        self.entities.pop(entity_id, None)
        self.removed += 1

    def update(self, entity):
        entity = plain(entity)
        self.entities[entity['id']] = entity

    def event(self, event):
        self.events.append(plain(event))
        del self.events[:-512]

    def set_menu(self, menu):
        self.menu = plain(menu)

    def accept(self, payload: bytes, now=None, baseline=False):
        result = self.core.accept(payload.decode('utf-8'), now if now is not None else time.monotonic() * 1000, baseline)
        return result if isinstance(result, tuple) else (result, '')

    def render(self, now=None):
        result = self.core.render(now if now is not None else time.monotonic() * 1000)
        return result if isinstance(result, tuple) else (result, '')

    def snapshot(self):
        return dict(sequence=self.core.sequence, generation=self.core.generation,
                    events_applied=self.core.events_applied, created=self.created, removed=self.removed,
                    menu=self.menu, entities=list(self.entities.values()), events=self.events,
                    view=plain(self.core.view()), visuals=plain(self.core.current['visuals']) if self.core.current else [],
                    full_game_renderer=False, real_guest_connected=False)


def receive_exact(stream, length):
    if not 0 <= length <= MAX_BYTES:
        raise ValueError('Frame exceeds receive budget')
    result = bytearray()
    while len(result) < length:
        data = stream.recv(min(length - len(result), 65536))
        if not data:
            raise EOFError('Scene connection closed')
        result.extend(data)
    return bytes(result)


def shared_read(path):
    """Allow the Lua writer to atomically retire this Windows file handle."""
    if os.name != 'nt':
        return path.read_bytes()
    import msvcrt
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    create = api.CreateFileW
    create.argtypes = [ctypes.c_wchar_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p,
                       ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p]
    create.restype = ctypes.c_void_p
    handle = create(str(path), 0x80000000, 7, None, 3, 0x80, None)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    fd = msvcrt.open_osfhandle(handle, os.O_RDONLY | os.O_BINARY)
    with os.fdopen(fd, 'rb') as stream:
        return stream.read(MAX_BYTES + 1)


class LocalLink:
    """File-to-wire development adapter; the renderer has no host-memory access.

    This transport is loopback only. Steam payload integration is a separate step.
    All callbacks into Lua run in the receiving/UI thread, not this relay thread.
    """
    def __init__(self, host_output: Path, client_output: Path, forward_preview=False):
        self.host_output, self.output = Path(host_output), Path(client_output)
        self.output.mkdir(parents=True, exist_ok=True)
        self.token = secrets.token_hex(24)
        self.stop_event = threading.Event()
        self.incoming = queue.Queue(maxsize=8)
        self.listener = socket.socket()
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1) if hasattr(socket, 'SO_EXCLUSIVEADDRUSE') else None
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(1)
        self.listener.settimeout(.2)
        self.port = self.listener.getsockname()[1]
        self.error = ''
        self.sent = self.received = 0
        self.forward_preview = forward_preview
        self.display_frames_skipped = 0
        self.threads = []

    def start(self):
        for action in (self.relay, self.receive):
            thread = threading.Thread(target=action, daemon=True)
            self.threads.append(thread)
            thread.start()

    def relay(self):
        try:
            while not self.stop_event.is_set():
                try:
                    stream, address = self.listener.accept()
                except socket.timeout:
                    continue
                with stream:
                    stream.settimeout(1)
                    if address[0] != '127.0.0.1' or receive_exact(stream, 48).decode('ascii') != self.token:
                        continue
                    previous = b''
                    while not self.stop_event.is_set():
                        path = self.host_output / 'scene-host.ac8w'
                        try:
                            if path.stat().st_size > MAX_BYTES:
                                raise ValueError('Host frame exceeds budget')
                            data = shared_read(path)
                        except OSError:
                            data = b''
                        if data and data != previous:
                            if len(data) > MAX_BYTES:
                                raise ValueError('Host frame exceeds budget')
                            stream.sendall(struct.pack('<I', len(data)) + data)
                            previous = data
                            self.sent += 1
                        self.stop_event.wait(.04)
        except (OSError, ValueError, UnicodeError, EOFError) as error:
            if not self.stop_event.is_set():
                self.error = str(error)

    def receive(self):
        try:
            with socket.create_connection(('127.0.0.1', self.port), timeout=1) as stream:
                stream.settimeout(.5)
                stream.sendall(self.token.encode('ascii'))
                # Timeout can split framing. Keep partial bytes across reads.
                buffer = bytearray()
                expected = None
                while not self.stop_event.is_set():
                    try:
                        data = stream.recv(65536)
                    except socket.timeout:
                        continue
                    if not data:
                        raise EOFError('Host relay closed')
                    buffer.extend(data)
                    while True:
                        if expected is None:
                            if len(buffer) < 4:
                                break
                            expected = struct.unpack_from('<I', buffer)[0]
                            del buffer[:4]
                            if not 1 <= expected <= MAX_BYTES:
                                raise ValueError('Invalid scene frame length')
                        if len(buffer) < expected:
                            break
                        payload = bytes(buffer[:expected])
                        del buffer[:expected]
                        expected = None
                        if self.forward_preview:
                            if not payload.startswith((b'AC8W\t1\t', b'AC8W\t2\t')) or not payload.endswith(b'\n'):
                                raise ValueError('Invalid replica payload framing')
                            # The UE codec validates this data before rendering.
                            # Forward reception independently of a hidden Tk UI.
                            path = self.host_output / 'scene-client-preview.ac8w'
                            temporary = path.with_name('scene-received-' + self.token + '.tmp')
                            temporary.write_bytes(payload)
                            try:
                                temporary.replace(path)
                            except PermissionError:
                                pass
                        try:
                            self.incoming.put_nowait(payload)
                        except queue.Full:
                            # Full snapshots include the event journal. The UI's
                            # core checks for event gaps before applying them.
                            self.incoming.get_nowait()
                            self.display_frames_skipped += 1
                            self.incoming.put_nowait(payload)
                        self.received += 1
        except (OSError, ValueError, EOFError, queue.Full) as error:
            if not self.stop_event.is_set():
                self.error = str(error)

    def close(self):
        self.stop_event.set()
        self.listener.close()
        for thread in self.threads:
            thread.join(timeout=1.5)


def positions(snapshot, width=800, height=450):
    entities = snapshot['entities']
    anchor = next((e for e in entities if e['role'] == 0), entities[0] if entities else None)
    center = anchor['position'] if anchor else (0, 0, 0)
    extent = max([200_000.] + [max(abs(e['position'][i] - center[i]) for i in (0, 1)) for e in entities])
    scale = min(width, height) * .42 / extent
    return [(e, width / 2 + (e['position'][1] - center[1]) * scale,
             height / 2 - (e['position'][0] - center[0]) * scale) for e in entities], extent / 100


def svg(snapshot, width=900, height=540):
    points, extent = positions(snapshot, width, height - 90)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
           '<rect width="100%" height="100%" fill="#101c2a"/>',
           '<g font-family="Segoe UI, sans-serif" fill="#d5e8f5">',
           '<text x="24" y="30" font-size="20">AC8 · Клиентская карта объектов (диагностика)</text>',
           f'<text x="24" y="55">Кадр {snapshot["sequence"]} · мир {snapshot["generation"]} · объектов {len(points)} · радиус {extent/1000:.1f} км</text>']
    for entity, x, y in points:
        color = '#62d4ff' if entity['role'] == 0 else '#73f3a2' if entity['role'] == 1 else '#efcb77'
        label = html.escape(entity['label'][:72])
        out.append(f'<circle cx="{x:.2f}" cy="{y+85:.2f}" r="5" fill="{color}"/><text x="{x+9:.2f}" y="{y+90:.2f}" font-size="12">{label}</text>')
    out.append('</g></svg>')
    return '\n'.join(out)


class SceneWindow:
    def __init__(self, window, host_output, output):
        import tkinter as tk
        from tkinter import ttk
        self.window, self.output = window, Path(output)
        self.replica = Replica()
        self.link = LocalLink(host_output, output, forward_preview=True)
        self.link.start()
        self.last_written = 0
        self.request = 0
        self.closed = False
        window.title('AC8 — Клиентская сцена · локальная диагностика')
        window.geometry('1000x760')
        self.status = tk.StringVar(value='Ожидание состояния хоста…')
        self.menu = tk.StringVar()
        self.stats = tk.StringVar()
        body = ttk.Frame(window, padding=14)
        body.pack(fill='both', expand=True)
        ttk.Label(body, text='Клиентская сцена', font=('Segoe UI', 19, 'bold')).pack(anchor='w')
        ttk.Label(body, text='Схематический вид из полученных пакетов · одна игра · без друга').pack(anchor='w')
        ttk.Label(body, textvariable=self.status).pack(anchor='w', pady=(8, 2))
        ttk.Label(body, textvariable=self.menu, wraplength=950).pack(anchor='w')
        ttk.Label(body, textvariable=self.stats).pack(anchor='w', pady=4)
        self.canvas = tk.Canvas(body, background='#101c2a', highlightthickness=0, height=380)
        self.canvas.pack(fill='both', expand=True)
        row = ttk.Frame(body); row.pack(fill='x', pady=8)
        ttk.Button(row, text='Камера гостя в игре', command=lambda: self.camera('guest')).pack(side='left')
        ttk.Button(row, text='Вернуть камеру хоста', command=lambda: self.camera('host')).pack(side='left', padx=8)
        ttk.Button(row, text='Клиентские модели в игре', command=lambda: self.camera('replica')).pack(side='left')
        ttk.Button(row, text='Сохранить клиентский снимок', command=self.save).pack(side='right')
        ttk.Label(body, text='В полёте: камера гостя на 15 с, клиентские модели на 12 с; затем возврат к хосту. Это локальная проверка, управление остаётся у хоста.', wraplength=950).pack(anchor='w')
        self.log = tk.Text(body, height=7, background='#f1f5f8', state='disabled')
        self.log.pack(fill='x', pady=(8, 0))
        self.last_events = 0
        window.protocol('WM_DELETE_WINDOW', self.close)
        self.tick()

    def camera(self, mode):
        self.request += 1
        # This is a narrow debug command, never a source-code mailbox.
        (self.link.host_output / 'scene-camera-command.tsv').write_text(
            f'request\t{self.request}\ncreated_unix\t{int(time.time())}\nmode\t{mode}\n', encoding='ascii')

    def save(self):
        snapshot = self.replica.snapshot()
        (self.output / 'client-scene.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        (self.output / 'client-scene.svg').write_text(svg(snapshot), encoding='utf-8')

    def tick(self):
        if self.closed:
            return
        try:
            for _ in range(8):
                try:
                    payload = self.link.incoming.get_nowait()
                except queue.Empty:
                    break
                accepted, reason = self.replica.accept(payload, baseline=self.replica.core.sequence == 0)
                if not accepted:
                    self.status.set('Состояние отклонено: ' + reason)
                else:
                    (self.output / 'scene-client.ac8w').write_bytes(payload)
            rendered, reason = self.replica.render()
            snapshot = self.replica.snapshot()
            self.status.set(('Получаю состояния хоста' if rendered else 'Нет свежих данных: ' + reason) +
                            (' · ' + self.link.error if self.link.error else ''))
            menu = snapshot['menu']
            if menu:
                self.menu.set(f'{STAGES[menu["stage"]]} · экран хоста: {menu["observed"]} · задание {menu["mission"]} · '
                              f'готовность: {menu["ready"] & 1}/{(menu["ready"] >> 1) & 1} · самолёт гостя: {menu["guest_aircraft"]}')
            self.stats.set(f'Кадр {snapshot["sequence"]} · мир {snapshot["generation"]} · объектов {len(snapshot["entities"])} · '
                           f'частей {len(snapshot.get("visuals") or [])} · событий {snapshot["events_applied"]} · TCP принято {self.link.received}')
            self.draw(snapshot)
            if snapshot['events_applied'] != self.last_events:
                self.log.configure(state='normal'); self.log.delete('1.0', 'end')
                for event in snapshot['events'][-30:]:
                    self.log.insert('end', f'{event["id"]:4}  {event["kind"]:<14} {event["entity"]:5}  {event["detail"][:160]}\n')
                self.log.see('end'); self.log.configure(state='disabled')
                self.last_events = snapshot['events_applied']
            if time.monotonic() - self.last_written > 1:
                self.save(); self.last_written = time.monotonic()
        except Exception as error:
            self.status.set('Ошибка клиентского состояния: ' + str(error))
            with (self.output / 'client-errors.log').open('a', encoding='utf-8') as log:
                log.write(str(error) + '\n')
        self.window.after(33, self.tick)

    def draw(self, snapshot):
        c = self.canvas; c.delete('all'); width, height = c.winfo_width(), c.winfo_height()
        for x in range(0, width, 60): c.create_line(x, 0, x, height, fill='#203044')
        for y in range(0, height, 60): c.create_line(0, y, width, y, fill='#203044')
        points, extent = positions(snapshot, width, height)
        for entity, x, y in points:
            color = '#62d4ff' if entity['role'] == 0 else '#73f3a2' if entity['role'] == 1 else '#efcb77'
            qx, qy, qz, qw = entity['rotation']; fx, fy = 1 - 2 * (qy*qy + qz*qz), 2 * (qx*qy + qw*qz)
            c.create_oval(x-4, y-4, x+4, y+4, fill=color, outline='')
            c.create_line(x, y, x+fy*22, y-fx*22, fill=color, width=2)
            if entity['role']<4:
                names={0:'Хост',1:'Гость · Бакстер',2:'Ведомый 2',3:'Ведомый 3'}
                c.create_text(x+9, y+(entity['role']-1)*13, text=names[entity['role']], fill=color, anchor='w', font=('Segoe UI', 10, 'bold'))
        c.create_text(12, 12, text=f'Вид сверху · радиус {extent/1000:.1f} км · зелёный — слот гостя', fill='#b1ccdd', anchor='nw')

    def close(self):
        if self.closed:
            return
        self.camera('host')
        self.closed = True
        self.save()
        self.link.close()
        self.window.destroy()


def main():
    import tkinter as tk
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host-output', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = tk.Tk()
    SceneWindow(root, args.host_output, args.output)
    root.mainloop()


if __name__ == '__main__':
    main()
