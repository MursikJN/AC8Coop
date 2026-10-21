"""Local guest panel. Uses the real native guest transport, never starts a second game."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import time
import tkinter as tk
from tkinter import ttk

REJECTIONS = {1: 'Действие доступно только хосту.', 2: 'Действие недоступно на текущем этапе.',
              3: 'Хост изменил настройки. Повторите действие.', 4: 'Неверный выбор самолёта.',
              5: 'Сначала выберите задание.', 6: 'Лимит сессии исчерпан.'}


def read_status(folder):
    path = folder / 'shared-session-status.tsv'
    try:
        data = path.read_text(encoding='ascii')
        if len(data) > 4096:
            return {}, 0
        return dict(line.split('\t', 1) for line in data.splitlines()), path.stat().st_mtime_ns
    except (OSError, ValueError):
        return {}, 0


def plane_name(key):
    return 'F-14D' if str(key) == '23' else ('Не выбран' if str(key) == '0' else 'Самолёт ID ' + str(key))


class GuestClient:
    def __init__(self, session_file):
        self.session = json.loads(Path(session_file).read_text(encoding='utf-8-sig'))
        self.output = Path(self.session['guest_output']).resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.dll_path = Path(self.session['guest_dll']).resolve()
        if hashlib.sha256(self.dll_path.read_bytes()).hexdigest().upper() != self.session['guest_dll_sha256']:
            raise ValueError('Хеш локального моста не совпадает. Пересоберите профиль.')
        if self.session['address'] != '127.0.0.1' or not 1 <= int(self.session['port']) <= 65535:
            raise ValueError('Разрешено только локальное соединение.')
        self.library = ctypes.CDLL(str(self.dll_path))
        for name in ('luaopen_ac8_local_start', 'luaopen_ac8_local_stop'):
            fn = getattr(self.library, name)
            fn.argtypes = [ctypes.c_void_p]
            fn.restype = ctypes.c_int
        self.library.ac8_local_wait_stopped.argtypes = [ctypes.c_ulong]
        self.library.ac8_local_wait_stopped.restype = ctypes.c_int
        self.snapshot = {}
        self.sequence = 0
        self.pending = None
        self.started_at = 0
        self.last_seen = 0
        self.last_stamp = 0
        self.active = False
        self.stopping = False
        self.message = 'Нажмите «Подключиться».'
        self.log('panel_open')

    def log(self, event, detail=''):
        with (self.output / 'guest-panel.log').open('a', encoding='utf-8') as stream:
            stream.write(time.strftime('%Y-%m-%d %H:%M:%S') + '\t' + event + '\t' + str(detail) + '\n')

    @property
    def connected(self):
        return self.active and not self.stopping and self.snapshot.get('connected') == '1' and self.snapshot.get('have_snapshot') == '1'

    def connect(self):
        if self.active or self.stopping:
            return
        os.environ.update(AC8_LOCAL_SESSION='25201480', AC8_LOCAL_ROLE='guest',
                          AC8_LOCAL_PORT=str(self.session['port']), AC8_LOCAL_TOKEN=str(self.session['token']),
                          AC8_COOP_RECON_OUTPUT=str(self.output))
        if self.session.get('mission_sync'):os.environ['AC8_MISSION_SYNC']='25201480'
        self.snapshot = {}
        self.sequence = 0
        self.pending = None
        self.started_at = time.time_ns()
        self.last_seen = time.monotonic()
        self.last_stamp = 0
        self.active = True
        self.message = 'Подключение к хосту…'
        self.library.luaopen_ac8_local_start(None)
        self.log('connect_requested')

    def disconnect(self):
        if not self.active:
            return
        self.library.luaopen_ac8_local_stop(None)
        self.stopping = True
        self.pending = None
        self.message = 'Отключение…'
        self.log('disconnect_requested')

    def poll(self):
        state, stamp = read_status(self.output)
        if not self.active or stamp < self.started_at or state.get('config_token') != str(self.session['token']) or time.time_ns() - stamp > 8_000_000_000:
            if self.active and time.monotonic() - self.last_seen > 8:
                self.snapshot = {}
                self.message = 'Нет ответа локального моста. Отключитесь и подключитесь повторно.'
            return
        if stamp > self.last_stamp:
            self.last_seen = time.monotonic()
            self.last_stamp = stamp
        self.snapshot = state
        self.sequence = max(self.sequence, int(state.get('request_ack', 0)))
        transport = state.get('transport')
        if transport == 'stopped':
            if not self.library.ac8_local_wait_stopped(0):
                return
            self.active = self.stopping = False
            self.message = 'Отключено. Можно подключиться повторно.'
            return
        if transport in ('error', 'disconnected'):
            if not self.library.ac8_local_wait_stopped(0):
                return
            self.active = self.stopping = False
            self.pending = None
            self.message = 'Соединение закрыто: ' + state.get('reason', '?')
            return
        if self.pending:
            request, began, description = self.pending
            if int(state.get('request_confirmed', 0)) >= request:
                rejection = int(state.get('reject', 0))
                self.message = REJECTIONS.get(rejection, 'Ошибка ' + str(rejection)) if rejection else 'Хост подтвердил: ' + description
                self.log('request_confirmed', f'{request} reject={rejection}')
                self.pending = None
            elif time.monotonic() - began > 8:
                self.message = 'Нет подтверждения команды от хоста. Проверьте соединение.'
                self.log('request_timeout', request)
                if not self.session.get('mission_sync'):self.pending = None
        elif self.connected and self.message.startswith('Подключение'):
            self.message = 'Соединение установлено. Выберите самолёт и нажмите «Готов».'

    def command(self, op, arg, description, arg1=0, expected=None):
        if not self.connected:
            raise ValueError('Сначала подключитесь к хосту.')
        if self.pending:
            raise ValueError('Дождитесь подтверждения предыдущего действия.')
        self.sequence += 1
        state = self.snapshot
        epoch,revision=expected or(state['epoch'],state['revision'])
        payload = dict(request=self.sequence, epoch=epoch, revision=revision, op=op, arg0=arg, arg1=arg1)
        data = ''.join(f'{key}\t{value}\n' for key, value in payload.items()).encode('ascii')
        (self.output / 'shared-session-command.tsv').write_bytes(data)
        self.pending = self.sequence, time.monotonic(), description
        self.message = 'Ожидание подтверждения хоста…'
        self.log('request_sent', json.dumps(payload))

    def choose_plane(self, plane):
        value = int(plane)
        if not 1 <= value <= 65535:
            raise ValueError('ID самолёта должен быть от 1 до 65535.')
        if self.session.get('hangar_adapter') and value != 23:
            raise ValueError('В штатном ангаре пока поддержан только F-14D.')
        self.command(3, value, plane_name(value))

    def ready(self):
        if int(self.snapshot.get('mission', 0)) == 0:
            raise ValueError('Хост ещё не выбрал задание.')
        if int(self.snapshot.get('phase', 0)) not in (0, 4):
            raise ValueError('Дождитесь открытия ангара или лобби.')
        ready = int(self.snapshot.get('ready_mask', 0)) & 2
        self.command(1, 0 if ready else 1, 'не готов' if ready else 'готов')


class GuestPanel:
    def __init__(self, root, client):
        self.root, self.client = root, client
        root.title('AC8 — Имитатор гостя')
        root.geometry('590x600')
        root.minsize(570, 580)
        style = ttk.Style(root)
        style.theme_use('clam')
        style.configure('.', font=('Segoe UI', 11))
        content = ttk.Frame(root, padding=20)
        content.pack(fill='both', expand=True)
        ttk.Label(content, text='Имитатор гостя', font=('Segoe UI', 20, 'bold')).pack(anchor='w')
        ttk.Label(content, text='Одна игра · локальное подключение · без второго Steam', foreground='#555').pack(anchor='w', pady=(3, 12))
        self.connection = tk.StringVar(value='Отключено')
        ttk.Label(content, textvariable=self.connection, font=('Segoe UI', 12, 'bold')).pack(anchor='w')
        self.connect_button = ttk.Button(content, text='Подключиться', command=self.toggle_connection)
        self.connect_button.pack(fill='x', pady=(8, 14))
        self.mission = tk.StringVar(value='Задание и сложность выбирает хост в игре.')
        ttk.Label(content, textvariable=self.mission).pack(anchor='w')
        self.stage = tk.StringVar(value='')
        if client.session.get('hangar_adapter'):
            ttk.Label(content, textvariable=self.stage, foreground='#245b86').pack(anchor='w', pady=(4, 0))
        self.readiness = tk.StringVar(value='Хост: —     Гость: —')
        ttk.Label(content, textvariable=self.readiness).pack(anchor='w', pady=(5, 12))
        ttk.Label(content, text='Самолёт гостя').pack(anchor='w')
        row = ttk.Frame(content);row.pack(fill='x', pady=5)
        self.aircraft = tk.StringVar(value='F-14D (23)')
        choices = ('F-14D (23)',) if client.session.get('hangar_adapter') else ('F-14D (23)', 'Другой ID для теста')
        self.combo = ttk.Combobox(row, textvariable=self.aircraft, state='readonly', values=choices)
        self.combo.pack(side='left', fill='x', expand=True)
        self.plane_id = tk.StringVar(value='23')
        self.id_entry = ttk.Spinbox(row, from_=1, to=65535, textvariable=self.plane_id, width=7, state='disabled')
        self.id_entry.pack(side='left', padx=(8, 0))
        self.combo.bind('<<ComboboxSelected>>', self.plane_changed)
        self.apply_button = ttk.Button(content, text='Выбрать самолёт', command=self.apply_plane)
        self.apply_button.pack(fill='x', pady=(3, 6))
        self.confirmed_plane = tk.StringVar(value='У хоста: не выбран')
        ttk.Label(content, textvariable=self.confirmed_plane).pack(anchor='w')
        self.ready_button = ttk.Button(content, text='Готов', command=lambda: self.action(client.ready))
        self.ready_button.pack(fill='x', pady=(12, 10))
        self.sync=None;self.sync_job=''
        if client.session.get('mission_sync'):
            from mission_sync_guest import SyncGuest
            self.sync=SyncGuest(client)
            root.geometry('630x850')
            controls=ttk.LabelFrame(content,text='Синхронизация: виртуальный гость',padding=8);controls.pack(fill='x',pady=5)
            for caption,key in [('Вступление, с',1),('Ангар, с',3),('Миссия, с',5),('Подтверждение старта, с','commit')]:
                row=ttk.Frame(controls);row.pack(fill='x');ttk.Label(row,text=caption).pack(side='left')
                value=tk.StringVar(value=str(self.sync.delays[key]/1000))
                def change(k=key,v=value):self.action(lambda:self.sync.set_delay(k,int(float(v.get())*1000)))
                spin=ttk.Spinbox(row,from_=0,to=60,increment=.5,textvariable=value,width=8,command=change);spin.pack(side='right');spin.bind('<FocusOut>',lambda _,fn=change:fn())
            ttk.Button(controls,text='Голос гостя за пропуск катсцены',command=lambda:self.action(self.sync.vote)).pack(fill='x',pady=4)
            ttk.Button(controls,text='Повторить последнюю команду',command=lambda:self.action(self.sync.repeat_last)).pack(fill='x')
            self.sync_detail=tk.StringVar(value='Ожидание первого этапа')
            ttk.Label(controls,textvariable=self.sync_detail,wraplength=520).pack(anchor='w',pady=4)
            root.after(15,self.sync_tick)
        self.message = tk.StringVar(value=client.message)
        ttk.Label(content, textvariable=self.message, wraplength=520, foreground='#245b86').pack(anchor='w')
        note = 'F-14D применяется к первому штатному ведомому в ангаре.\nВ ангаре нужна новая готовность. Вылет подтверждает хост.' if client.session.get('hangar_adapter') else 'Проверяет сетевой выбор. Ангар и самолёт в игре пока не меняет.\nF-14D подтверждён; остальные ID — только для проверки протокола.'
        ttk.Label(content, text=note,
                  wraplength=520, foreground='#666', font=('Segoe UI', 9)).pack(anchor='w', pady=(12, 0))
        root.protocol('WM_DELETE_WINDOW', self.close)
        self.scene_window = None
        if client.session.get('scene_viewer'):
            from scene_viewer import SceneWindow
            self.scene_window = SceneWindow(tk.Toplevel(root), client.session['host_output'],
                                            Path(client.session['guest_output']) / 'scene')
        self.update()

    def action(self, callback):
        try:
            callback()
        except (ValueError, OSError, KeyError) as problem:
            self.client.message = str(problem)
            self.client.log('panel_error', problem)

    def sync_tick(self):
        if not self.root.winfo_exists():return
        if self.client.stopping:self.root.after(15,self.sync_tick);return
        self.client.poll()
        self.action(self.sync.update)
        path=self.client.output/'simulator-command.json'
        try:
            text=path.read_text(encoding='utf-8')
            if len(text)<=4096:
                job=json.loads(text);identifier=job.get('id')
                if isinstance(identifier,str)and identifier!=self.sync_job and job.get('token')==str(self.client.session['token']):
                    self.sync_job=identifier;action=job.get('action')
                    def run():
                        if action=='connect':self.client.connect()
                        elif action=='plane':self.client.choose_plane(23)
                        elif action=='ready':self.client.ready()
                        elif action=='vote':self.sync.vote()
                        elif action=='repeat':self.sync.repeat_last()
                        elif action=='delay':self.sync.set_delay(job['key'],int(job['milliseconds']))
                        else:raise ValueError('Неизвестная команда имитатора.')
                    self.action(run);self.client.log('simulator_job',identifier+'/'+str(action))
        except(FileNotFoundError,PermissionError,json.JSONDecodeError):pass
        s=self.client.snapshot
        count=lambda key:str(bin(int(s.get(key,0))).count('1'))
        self.sync_detail.set('Загрузка: '+count('loaded_mask')+'/2 · Подтверждения: '+count('commit_mask')+'/2 · Голоса: '+count('vote_mask')+'/2\nЭто имитатор; второй игровой мир не рисуется.')
        self.root.after(15,self.sync_tick)

    def toggle_connection(self):
        self.action(self.client.disconnect if self.client.active else self.client.connect)

    def plane_changed(self, _event=None):
        custom = self.aircraft.get() != 'F-14D (23)'
        self.id_entry.configure(state='normal' if custom else 'disabled')
        if not custom:
            self.plane_id.set('23')

    def apply_plane(self):
        self.action(lambda: self.client.choose_plane(self.plane_id.get()))

    def update(self):
        if (self.client.output / 'close-panel').exists():
            self.close();return
        self.client.poll()
        state = self.client.snapshot
        connected = self.client.connected
        mask = int(state.get('ready_mask', 0))
        self.connection.set('Подключён к 127.0.0.1:' + str(self.client.session['port']) if connected else ('Подключение…' if self.client.active else 'Отключено'))
        self.connect_button.configure(text='Отключиться' if self.client.active else 'Подключиться', state='disabled' if self.client.stopping else 'normal')
        phase = int(state.get('phase', 0))
        enabled = connected and not self.client.pending and phase in (0, 4)
        self.apply_button.configure(state='normal' if enabled else 'disabled')
        self.ready_button.configure(state='normal' if enabled and int(state.get('mission', 0)) else 'disabled', text='Снять готовность' if mask & 2 else 'Готов')
        difficulties = {'1': 'ПИЛОТ', '2': 'ВЕТЕРАН', '3': 'ЭЛИТА', '4': 'НОВИЧОК (СЮЖЕТ)'}
        if connected:
            stages = {0:'Лобби: дождитесь перехода хоста в ангар.',3:'Открытие и настройка штатного ангара…',4:'Ангар: подтвердите готовность заново.',5:'Хост начинает миссию…',6:'Миссия запущена на хосте.',8:'Сессия остановлена.'}
            self.stage.set(stages.get(phase, 'Загрузка…'))
            self.mission.set('Задание ' + state.get('mission', '—') + ' · ' + difficulties.get(state.get('difficulty'), '—'))
            self.readiness.set('Хост: ' + ('✓ Готов' if mask & 1 else 'Не готов') + '     Гость: ' + ('✓ Готов' if mask & 2 else 'Не готов'))
            self.confirmed_plane.set('У хоста: ' + plane_name(state.get('guest_aircraft', '0')))
        else:
            self.mission.set('Задание и сложность выбирает хост в игре.')
            self.readiness.set('Хост: —     Гость: —')
            self.confirmed_plane.set('У хоста: —')
        self.message.set(self.client.message)
        self.root.after(150, self.update)

    def close(self):
        if self.scene_window and not self.scene_window.closed:
            self.scene_window.close()
        self.client.disconnect()
        self.client.log('panel_close')
        self.finish_close()

    def finish_close(self):
        if self.client.library.ac8_local_wait_stopped(0):
            self.root.destroy()
        else:
            self.root.after(50, self.finish_close)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', required=True, type=Path)
    args = parser.parse_args()
    client = GuestClient(args.session)
    root = tk.Tk()
    GuestPanel(root, client)
    root.mainloop()


if __name__ == '__main__':
    main()
