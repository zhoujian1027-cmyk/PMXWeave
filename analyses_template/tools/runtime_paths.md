# Runtime setup

Model authoring in chat does not require an R runtime. Reports require R, the
analysis packages, a C++ compiler, Pandoc, Node.js, Python 3 and a POSIX shell.
Use the study/output directory authorized by the user. The agent reads the
toolkit and explicitly named study and writes study artifacts beside the data.

## Local R deployment

With R and its dependencies installed on the agent host:

~~~sh
Rscript analyses_template/tools/install_dependencies.R --check
python3 analyses_template/tools/runtime/worker.py --studies /absolute/studies
~~~

Keep the worker running under the host's service manager. Use an external JSON
with queue_root set to /absolute/studies/.pmx-runtime, workspace_root set to
/absolute/studies, execution set to local, and path_mappings set to [].
Set PMX_RUNTIME_CONFIG to the agent-visible JSON path. You can also use the
Git-ignored local pointer shown below. To install missing R packages, run
the installation helper with --install.

## Optional Docker deployment

Run these owner commands on the Docker host once. Replace the sample paths;
the toolkit folder may have any name. The R library must match the worker's
R version and platform.

~~~sh
docker build -t pmxweave-r-runtime:4.5.1 analyses_template/tools/runtime
docker run --rm \
  --mount type=bind,src=/host/R/library,dst=/usr/local/lib/R/site-library \
  --mount type=bind,src=/host/PMXWeave,dst=/pmx/toolkit,readonly \
  --entrypoint Rscript pmxweave-r-runtime:4.5.1 \
  /pmx/toolkit/analyses_template/tools/install_dependencies.R --install

python3 analyses_template/tools/runtime/deploy_docker.py \
  --studies /host/studies \
  --client-studies /agent-visible/studies \
  --library /host/R/library \
  --config /host/private/pmx-runtime.json
~~~

The deployer starts a serial, restartable R worker. Only the study tree is
writable; the R library and worker source are read-only. Its queue, logs,
results and R temporary files stay under <studies>/.pmx-runtime/.
Deployment does not run an analysis or modify input data. Use --uid and --gid
with the host share owner IDs when deploying as an administrator. The selected
study directory and its generated outputs must be writable by this account. No network port,
Docker socket or RStudio login is exposed to the agent.

Make the JSON readable at a known path in the agent environment and set
PMX_RUNTIME_CONFIG to that path. Alternatively, the deployment owner can create
the Git-ignored .pmx-runtime.local.json in the toolkit root:

~~~json
{"runtime_config": "/agent-visible/private/pmx-runtime.json"}
~~~

The JSON owns queue_root, workspace_root, execution, path_mappings and
r_container. Client paths are the agent's paths; worker paths are the R
container's paths. Do not use host paths on the client. Deployment settings
are excluded from Git. Moving or renaming the toolkit does not require changing
internal paths. Moving studies requires redeploying their mount and updating
the runtime JSON.

## Study path access

Agent filesystem permissions belong to the user and the host agent application.
The PMX preset does not add a path whitelist or parse prompts to grant directory
access. With Deepseek harness Full Access, a user-named study need not be inside the toolkit
or current workspace. Follow the user's task boundaries when reading/writing.
For workspace-write mode, the native writable boundary must cover the study;
selecting a common parent project is one option in that mode, not a requirement
for Full Access. A genuinely absent path or missing OS permission remains an
actual filesystem error.

R mount mappings describe what the execution worker can see. They do not
authorize or deny the agent's ordinary file tools. Never replace a supplied
study path with toolkit/example or infer the study root from the queue.

## Verify and troubleshoot

~~~sh
node analyses_template/tools/runtime_check.mjs /agent-visible/studies/ppk
~~~

PMX_RUNTIME_OK checks configuration, mapping and a live worker heartbeat. It
does not certify analysis results or all installed packages. Check dependencies
with the installation helper in the actual worker environment. Use report
wrappers and returned job IDs; do not manually search queue storage or resubmit
a running job.

- PMX_RUNTIME_REQUIRED: set the external JSON path or ignored local pointer.
- RPATH_OFF_MOUNT: check the path mapping and the worker’s mounted study directory.
- Stale heartbeat: check the local worker logs. For Docker, run
  docker logs pmxweave-r-worker on the Docker host using the configured worker name.
- File access error: check the host agent permission setting and actual path;
  PMX does not require a separate directory whitelist.
- Word package load error: repair worker system libraries and resume Word
  generation using completed analysis outputs.

Jobs marked running before a worker interruption are not automatically
replayed. Review the interrupted job before explicitly submitting a new one.
