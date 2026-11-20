#!/usr/bin/python3
"""Unprivileged PTY over the existing host-key-pinned SSH exec stream.

Only terminal input and uint16 window dimensions cross stdin. Output remains
raw VT for the host security filter. No Node, daemon, root, file or network API.
"""
import errno
import fcntl
import os
import pty
import selectors
import signal
import struct
import sys
import termios

MAX_FRAME = 32769
LIMIT = 131072


def read_exact(count):
    result = bytearray()
    while len(result) < count:
        data = os.read(0, count - len(result))
        if not data:
            raise EOFError()
        result.extend(data)
    return result


def window(body):
    if len(body) != 5 or body[0] != 2:
        raise ValueError('window frame')
    columns, rows = struct.unpack('!HH', body[1:])
    if not columns or not rows:
        raise ValueError('zero window')
    return struct.pack('HHHH', rows, columns, 0, 0)


def main():
    # Read dimensions BEFORE fork/exec, so even the first application query is
    # correct. Windows ssh.exe itself needs no console and requests no SSH PTY.
    length = struct.unpack('!I', read_exact(4))[0]
    if length != 5:
        raise ValueError('initial window required')
    initial = window(read_exact(length))
    pid, master = pty.fork()
    if pid == 0:
        try:
            fcntl.ioctl(0, termios.TIOCSWINSZ, initial)
            os.chdir('/home/sandbox/workspaces')
            env = os.environ.copy()
            env['HOME'] = '/home/sandbox'
            env['TERM'] = 'xterm-256color'
            os.execve('/bin/bash', ['bash', '-l'], env)
        finally:
            os._exit(126)
    fcntl.ioctl(master, termios.TIOCSWINSZ, initial)
    for fd in (0, 1, master):
        os.set_blocking(fd, False)
    incoming = bytearray()
    to_pty = bytearray()
    to_host = bytearray()
    child_status = None
    terminal_end = False
    closing = False
    poll = selectors.DefaultSelector()

    def stop(signum, unused):
        nonlocal closing
        closing = True

    for signum in (signal.SIGHUP, signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, stop)

    def watch(fd, events):
        try:
            poll.get_key(fd)
            if events:
                poll.modify(fd, events)
            else:
                poll.unregister(fd)
        except KeyError:
            if events:
                poll.register(fd, events)

    def parse_input():
        while len(incoming) >= 4:
            count = struct.unpack('!I', incoming[:4])[0]
            if not 1 <= count <= MAX_FRAME:
                raise ValueError('frame limit')
            if len(incoming) < count + 4:
                break
            body = bytes(incoming[4:count + 4])
            if body[0] == 1:
                if len(to_pty) + len(body) - 1 > LIMIT:
                    break  # Backpressure, not a cap on legitimate paste size.
                to_pty.extend(body[1:])
            elif body[0] == 2:
                fcntl.ioctl(master, termios.TIOCSWINSZ, window(body))
            else:
                raise ValueError('frame type')
            del incoming[:count + 4]

    try:
        while not closing:
            if terminal_end:
                incoming.clear()
                to_pty.clear()
            else:
                parse_input()
            if child_status is None:
                found, status = os.waitpid(pid, os.WNOHANG)
                if found:
                    child_status = status
            if terminal_end and not to_host:
                break
            watch(0, selectors.EVENT_READ if len(incoming) < LIMIT and len(to_pty) < LIMIT and child_status is None else 0)
            watch(master, (selectors.EVENT_READ if not terminal_end and len(to_host) < LIMIT else 0) | (selectors.EVENT_WRITE if to_pty and not terminal_end else 0))
            watch(1, selectors.EVENT_WRITE if to_host else 0)
            for key, events in poll.select(0.2):
                fd = key.fd
                try:
                    if fd == 0:
                        data = os.read(0, min(32768, LIMIT - len(incoming)))
                        if not data:
                            closing = True
                            break
                        incoming.extend(data)
                        parse_input()
                    elif fd == master:
                        if events & selectors.EVENT_READ:
                            try:
                                data = os.read(master, min(32768, LIMIT - len(to_host)))
                            except OSError as error:
                                if error.errno != errno.EIO:
                                    raise
                                data = b''
                            if data:
                                to_host.extend(data)
                            else:
                                terminal_end = True
                        if events & selectors.EVENT_WRITE and to_pty and not terminal_end:
                            sent = os.write(master, to_pty)
                            del to_pty[:sent]
                    elif fd == 1:
                        sent = os.write(1, to_host)
                        del to_host[:sent]
                except BlockingIOError:
                    pass
        if terminal_end and child_status is None:
            import time
            until = time.monotonic() + 3
            while time.monotonic() < until:
                found, status = os.waitpid(pid, os.WNOHANG)
                if found:
                    child_status = status
                    break
                time.sleep(0.01)
        result = os.waitstatus_to_exitcode(child_status) if child_status is not None else 0
        return 128 - result if result < 0 else result
    finally:
        poll.close()
        os.close(master)  # Hang up this terminal, not the VM or other sessions.
        if child_status is None:
            try:
                os.kill(pid, signal.SIGHUP)
            except ProcessLookupError:
                pass
            # A client disconnect must not leave a detached shell relay behind.
            import time
            until = time.monotonic() + 3
            while time.monotonic() < until:
                found, unused = os.waitpid(pid, os.WNOHANG)
                if found:
                    break
                time.sleep(0.05)
            else:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                os.waitpid(pid, 0)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, EOFError, BrokenPipeError, OSError):
        sys.stderr.write('Portable terminal relay failed; no alternate shell.\n')
        raise SystemExit(1)
