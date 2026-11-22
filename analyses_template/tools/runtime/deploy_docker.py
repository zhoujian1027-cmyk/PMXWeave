#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import subprocess

def main():
    parser = argparse.ArgumentParser(description="Deploy the PMXWeave R queue worker on a Docker host.")
    parser.add_argument("--studies", required=True, help="Host path of the external analysis directory")
    parser.add_argument("--client-studies", required=True, help="The same directory as seen by the AI agent")
    parser.add_argument("--library", required=True, help="Installed R library on the host")
    parser.add_argument("--config", required=True, help="Host destination of the external runtime JSON")
    parser.add_argument("--image", default="pmxweave-r-runtime:4.5.1")
    parser.add_argument("--name", default="pmxweave-r-worker")
    parser.add_argument("--uid", type=int, default=os.getuid())
    parser.add_argument("--gid", type=int, default=os.getgid())
    args = parser.parse_args()
    studies = Path(args.studies).resolve(strict=True)
    library = Path(args.library).resolve(strict=True)
    source = Path(__file__).resolve().parent
    client = Path(args.client_studies)
    if not client.is_absolute():
        parser.error("--client-studies must be absolute")
    for name in ("requests", "results", "logs", "status", "scripts", "tmp"):
        (studies / ".pmx-runtime" / name).mkdir(parents=True, exist_ok=True)
    if subprocess.run(["docker", "container", "inspect", args.name],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        parser.error("container already exists; inspect or stop it explicitly before redeployment")
    for directory, dirs, files in os.walk(studies / ".pmx-runtime"):
        os.chown(directory, args.uid, args.gid)
        os.chmod(directory, 0o775)
        for name in files:
            os.chown(Path(directory) / name, args.uid, args.gid)
    command = ["docker", "run", "-d", "--name", args.name, "--restart", "unless-stopped",
        "--user", f"{args.uid}:{args.gid}",
        "--env", "HOME=/pmx/studies/.pmx-runtime/tmp",
        "--env", "PYTHONDONTWRITEBYTECODE=1",
        "--read-only", "--tmpfs", "/tmp:rw,nosuid,size=512m",
        "--mount", f"type=bind,src={studies},dst=/pmx/studies",
        "--mount", f"type=bind,src={library},dst=/usr/local/lib/R/site-library,readonly",
        "--mount", f"type=bind,src={source},dst=/opt/pmx-runtime,readonly",
        "--entrypoint", "python3", args.image, "/opt/pmx-runtime/worker.py",
        "--studies", "/pmx/studies", "--client-studies", str(client)]
    subprocess.run(command, check=True)
    config = Path(args.config).resolve()
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(json.dumps({
        "queue_root": str(client / ".pmx-runtime"),
        "workspace_root": str(client),
        "execution": "mapped",
        "path_mappings": [{"client": str(client), "worker": "/pmx/studies"}],
        "r_container": args.name
    }, indent=2) + "\n")
    print("Runtime JSON:", config)
    print("Set PMX_RUNTIME_CONFIG to its agent-visible path, or create the ignored local pointer.")
    print("Verify R packages before submitting reports; deployment does not install them.")

if __name__ == "__main__":
    main()
