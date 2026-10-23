"""Read-only window/desktop metadata; never activates, switches or injects input."""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--pid', type=int, required=True)
a = p.parse_args()
u = c.WinDLL('user32', use_last_error=True)
k = c.WinDLL('kernel32', use_last_error=True)
u.GetThreadDesktop.argtypes = [w.DWORD]; u.GetThreadDesktop.restype = w.HANDLE
u.OpenInputDesktop.argtypes = [w.DWORD, w.BOOL, w.DWORD]; u.OpenInputDesktop.restype = w.HANDLE
u.CloseDesktop.argtypes = [w.HANDLE]
u.GetUserObjectInformationW.argtypes = [w.HANDLE, c.c_int, w.LPVOID, w.DWORD, c.POINTER(w.DWORD)]
u.GetWindowThreadProcessId.argtypes = [w.HWND, c.POINTER(w.DWORD)]; u.GetWindowThreadProcessId.restype = w.DWORD
u.GetWindowTextW.argtypes = [w.HWND, w.LPWSTR, c.c_int]
u.GetClassNameW.argtypes = [w.HWND, w.LPWSTR, c.c_int]
u.IsWindowVisible.argtypes = [w.HWND]; u.IsIconic.argtypes = [w.HWND]
u.GetWindowRect.argtypes = [w.HWND, c.POINTER(w.RECT)]
k.GetCurrentThreadId.restype = w.DWORD

def desktop(handle):
    if not handle:
        return {'error': c.get_last_error()}
    buf = c.create_unicode_buffer(512); needed = w.DWORD()
    if not u.GetUserObjectInformationW(handle, 2, buf, c.sizeof(buf), c.byref(needed)):
        return {'error': c.get_last_error()}
    return buf.value

windows = []
@c.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
def visit(hwnd, _):
    pid = w.DWORD(); tid = u.GetWindowThreadProcessId(hwnd, c.byref(pid))
    if pid.value == a.pid:
        title = c.create_unicode_buffer(1024); cls = c.create_unicode_buffer(256); rect = w.RECT()
        u.GetWindowTextW(hwnd, title, len(title)); u.GetClassNameW(hwnd, cls, len(cls)); u.GetWindowRect(hwnd, c.byref(rect))
        windows.append(dict(hwnd=hwnd, thread=tid, desktop=desktop(u.GetThreadDesktop(tid)),
                            title=title.value, window_class=cls.value, visible=bool(u.IsWindowVisible(hwnd)),
                            minimized=bool(u.IsIconic(hwnd)), rect=[rect.left, rect.top, rect.right, rect.bottom]))
    return True

u.EnumWindows.argtypes = [type(visit), w.LPARAM]
u.EnumWindows(visit, 0)
input_handle = u.OpenInputDesktop(0, False, 1)
input_name = desktop(input_handle)
if input_handle: u.CloseDesktop(input_handle)
print(json.dumps(dict(pid=a.pid, caller_desktop=desktop(u.GetThreadDesktop(k.GetCurrentThreadId())),
                      input_desktop=input_name, windows=windows), ensure_ascii=False, indent=2))
