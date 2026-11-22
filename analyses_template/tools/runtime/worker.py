#!/usr/bin/env python3
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

def stamp():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def publish(dest, value):
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    tmp.write_text(json.dumps(value, indent=1))
    os.chmod(tmp, 0o664)
    tmp.replace(dest)

def beneath(path, root):
    return path == root or root in path.parents

def main():
    os.umask(0o002)
    parser = argparse.ArgumentParser()
    parser.add_argument("--studies", required=True)
    parser.add_argument("--client-studies")
    parser.add_argument("--queue")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    studies = Path(args.studies).resolve(strict=True)
    client = Path(args.client_studies or args.studies)
    queue = Path(args.queue or studies / ".pmx-runtime").resolve()
    if not beneath(queue, studies) or args.timeout < 1:
        parser.error("queue must be inside the studies directory; timeout must be positive")
    for name in ("requests", "results", "logs", "status", "scripts", "tmp"):
        (queue / name).mkdir(parents=True, exist_ok=True)
    os.environ["TMPDIR"] = str(queue / "tmp")
    lock = (queue / "scripts/worker.lock").open("a")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    active = None

    def health():
        publish(queue / "scripts/r-run-state.json",
                {"container_running": True, "last_check": stamp(),
                 "last_check_epoch": int(time.time()), "worker_timeout_s": args.timeout,
                 "active_id": active, "worker": "pmxweave"})

    while True:
        health()
        for request in sorted((queue / "requests").glob("*.json"), key=lambda p: p.stat().st_mtime):
            job = request.stem
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.~-]*", job):
                continue
            result = queue / "results" / (job + ".json")
            status_file = queue / "status" / (job + ".json")
            if result.exists():
                continue
            out = queue / "logs" / (job + ".out")
            err = queue / "logs" / (job + ".err")
            started = stamp()
            t0 = time.monotonic()
            active = job
            proc = None
            state, rc, signo = "error", 1, None
            try:
                if status_file.exists() and json.loads(status_file.read_text()).get("state") == "running":
                    raise RuntimeError("WORKER_INTERRUPTED: prior worker stopped; review this job before resubmitting")
                payload = json.loads(request.read_text())
                if payload.get("id") != job or not isinstance(payload.get("code"), str):
                    raise ValueError("invalid request")
                client_dir = Path(payload["cwd"]) if payload.get("purpose") == "standalone_model_structure" and "cwd" in payload else Path(payload["src"]).parent
                relative = client_dir.relative_to(client)
                workdir = (studies / relative).resolve(strict=True)
                if not workdir.is_dir() or not beneath(workdir, studies) or beneath(workdir, queue):
                    raise ValueError("job directory must be inside the mounted studies")
                code = queue / "logs" / (job + ".R")
                code.write_text(payload["code"])
                with out.open("w") as stdout, err.open("w") as stderr:
                    proc = subprocess.Popen(["Rscript", "--vanilla", str(code)], cwd=workdir,
                                            stdout=stdout, stderr=stderr, start_new_session=True)
                    def progress():
                        publish(status_file, {"id": job, "state": "running", "started": started,
                            "updated": stamp(), "elapsed_s": int(time.monotonic()-t0),
                            "out_bytes": out.stat().st_size, "err_bytes": err.stat().st_size,
                            "worker_pid": os.getpid()})
                        health()
                    progress()
                    while proc.poll() is None:
                        if time.monotonic()-t0 > args.timeout:
                            os.killpg(proc.pid, signal.SIGKILL)
                            proc.wait()
                            state, rc, signo = "timeout", 124, 9
                            break
                        time.sleep(1)
                        progress()
                    else:
                        rc = proc.returncode
                        signo = -rc if rc < 0 else None
                        state = "ok" if rc == 0 else ("crashed" if rc < 0 else "error")
            except Exception as exc:
                with err.open("a") as stream:
                    stream.write(str(exc) + "\n")
            finally:
                if proc is not None:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                def tail(file):
                    if not file.exists():
                        return ""
                    with file.open("rb") as stream:
                        stream.seek(max(0, file.stat().st_size-200000))
                        return stream.read().decode(errors="replace")
                final = {"id": job, "state": state, "status": state, "exit": rc, "signal": signo,
                         "took_s": round(time.monotonic()-t0, 2), "finished": stamp(),
                         "stdout": tail(out), "stderr": tail(err), "log": str(out)}
                publish(result, final)
                publish(status_file, {k: v for k, v in final.items() if k not in ("stdout", "stderr")})
                active = None
                health()
        time.sleep(2)

if __name__ == "__main__":
    main()
