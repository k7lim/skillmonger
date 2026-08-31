#!/usr/bin/env python3
"""One writer at a time per skill directory -- the python side of the lock.

scripts/lib/skill-lock.sh is the bash side; both use `<skill-dir>/.lock/`, a
directory because mkdir is atomic everywhere and `flock` is not on macOS.
The two must agree on the path and on the two settings:

  SKILLMONGER_LOCK_WAIT   seconds to wait for a held lock (default 60)
  SKILLMONGER_LOCK_STALE  age past which a lock is a dead holder's (default 120)

A stale lock is stolen by renaming it away first, so two waiters that both
see it stale cannot both remove it and both acquire.

    with SkillLock(skill_dir):
        ... read, modify, write ...
"""

from __future__ import annotations

import os
import shutil
import sys
import time


DEFAULT_WAIT = 60
DEFAULT_STALE = 120
POLL_SECONDS = 0.05


class SkillLockTimeout(RuntimeError):
    pass


def _setting(name, default):
    raw = os.environ.get(name, "").strip()
    try:
        return float(raw) if raw else float(default)
    except ValueError:
        return float(default)


def lock_path(skill_dir):
    return os.path.join(skill_dir, ".lock")


class SkillLock:
    def __init__(self, skill_dir, wait=None, stale=None, warn=None):
        self.skill_dir = skill_dir
        self.lock = lock_path(skill_dir)
        self.wait = _setting("SKILLMONGER_LOCK_WAIT", DEFAULT_WAIT) if wait is None else wait
        self.stale = _setting("SKILLMONGER_LOCK_STALE", DEFAULT_STALE) if stale is None else stale
        self.warn = warn or (lambda message: sys.stderr.write(f"  warning: {message}\n"))
        self.held = False

    def _holder(self, lock=None):
        try:
            with open(os.path.join(lock or self.lock, "pid"), "r") as handle:
                return handle.read().strip() or "?"
        except OSError:
            return "?"

    def _is_stale(self):
        try:
            return time.time() - os.stat(self.lock).st_mtime >= self.stale
        except OSError:
            return False

    def acquire(self):
        deadline = time.time() + self.wait
        while True:
            try:
                os.mkdir(self.lock)
                break
            except FileExistsError:
                pass
            if self._is_stale():
                stale = f"{self.lock}.stale.{os.getpid()}"
                try:
                    os.rename(self.lock, stale)
                except OSError:
                    continue  # another waiter won the rename
                self.warn(f"removed stale lock {self.lock} (pid {self._holder(stale)})")
                shutil.rmtree(stale, ignore_errors=True)
                continue
            if time.time() >= deadline:
                raise SkillLockTimeout(
                    f"could not lock {self.skill_dir} after {self.wait:g}s; "
                    f"held by pid {self._holder()} at {self.lock}"
                )
            time.sleep(POLL_SECONDS)
        try:
            with open(os.path.join(self.lock, "pid"), "w") as handle:
                handle.write(f"{os.getpid()}\n")
        except OSError:
            pass
        self.held = True
        return self

    def release(self):
        if self.held:
            shutil.rmtree(self.lock, ignore_errors=True)
            self.held = False

    def __enter__(self):
        return self.acquire()

    def __exit__(self, *exc):
        self.release()
        return False
