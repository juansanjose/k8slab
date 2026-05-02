# Agent Instructions

When inspecting logs for processes running inside SSH instances, do not wait passively for long periods after gathering enough evidence to act.

- Read the recent logs, identify the current state, and decide on the next action promptly.
- If a process appears stuck, idle, repeatedly failing, or waiting on a missing dependency, take a corrective action instead of continuing to watch logs.
- If more observation is genuinely needed, use a short, explicit time box and state what signal you are waiting for.
- Prefer active checks such as process status, exit codes, health endpoints, disk usage, GPU usage, or service logs over extended passive tailing.
- After taking action, summarize what was observed, what action was taken, and what remains to verify.

## Secret Hygiene

Do not add real credentials, tokens, API keys, kubeconfigs, SSH keys, Tailscale auth keys, RunPod keys, Vast.ai keys, k3s node tokens, or Kubernetes Secret manifests with live values to Git.

- Keep real secrets in local files covered by `.gitignore`, a local secret manager, or the provider's expected home-directory config.
- Commit only examples, templates, or placeholders such as `.env.example`, `secret.example.yaml`, or values like `YOUR_API_KEY`.
- Before committing or pushing, run `git status --ignored` and inspect any new or modified files whose names include `secret`, `token`, `key`, `credential`, `kubeconfig`, `tailscale`, `runpod`, or `vast`.
- Also inspect file contents for Kubernetes Secret manifests, especially `kind: Secret`, `stringData`, `data`, or provider-specific credential fields, even when the filename looks generic.
- If a real secret is accidentally staged or committed, stop and remove it from the branch history before pushing. If it was already pushed, treat it as compromised and rotate it.
