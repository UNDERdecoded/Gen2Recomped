#!/usr/bin/env python3
"""Deterministic user maintenance; no network or AI task is involved."""
import argparse
import contextlib
import logging
import json
import os
import shutil
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path
from qa_storage import Storage


class LogWriter:
    def __init__(self, logger):self.logger = logger
    def write(self, value):
        for line in value.splitlines():
            if line.strip():self.logger.info('%s', line[:2000])
        return len(value)
    def flush(self):pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    state = Path.home()/'.cache/origami-qa-storage';state.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger('qa-maintenance');logger.setLevel(logging.INFO)
    handler = RotatingFileHandler(state/'maintenance.log', maxBytes=2*1024*1024, backupCount=1)
    handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'));logger.addHandler(handler)
    storage = None
    try:
        with contextlib.redirect_stdout(LogWriter(logger)), contextlib.redirect_stderr(LogWriter(logger)):
            storage = Storage(args.root)
            checked=[]
            for root in set(storage._registered_roots()):
                try:
                    with os.scandir(root) as entries:next(entries,None)
                except FileNotFoundError:continue
                checked.append(str(root))
            reclaimed = storage.sweep()
            status=state/'maintenance';status.mkdir(exist_ok=True)
            temp=status/'status.tmp'
            temp.write_text(json.dumps(dict(time=time.time(),checked_roots=sorted(checked),
                reclaimed_logical_bytes=reclaimed,free_bytes=shutil.disk_usage(args.root).free),indent=2))
            temp.replace(status/'status.json')
            logger.info('Sweep complete; reclaimed %.1f MiB of logical idle payloads', reclaimed/1024**2)
        return 0
    except Exception:
        logger.exception('Maintenance failed; copies are retained for retry')
        return 1
    finally:
        if storage is not None:storage.close(collect=False)
        handler.close();logger.removeHandler(handler)


if __name__ == '__main__':raise SystemExit(main())
