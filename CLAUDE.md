# fde-lab

A personal lab for forward deployed engineer (FDE) skills: taking models and AI systems into a customer's environment and making them work there.

## Scope

- Deployment first: running and serving models on cloud infra. Nothing runs locally. Development (building on top of models) comes later.
- Cloud: RunPod to start (2026-11-15). Hyperscalers may come later.
- Infra as code with OpenTofu in `infra/`; `runpodctl` for one-off tasks (logs, file transfer, SSH). Both read `RUNPOD_API_KEY` from the gitignored `mise.local.toml`.
- Runtime: vLLM to start (2026-11-15).
- Separate from `../gke-lab` by choice. Reuse what it teaches; don't merge them.
- Scope beyond that isn't set. The user sets the direction and designs the lab; propose options, don't pick them.

## Workflow

- Commit after every meaningful change (a finished, working step), without waiting to be asked. Stage files by name.
- Scratch space is `tmp/` in this repo (gitignored), not the system temp dir.
- Model weights stay out of git: `models/` and weight files are gitignored.
- Ask before large downloads (several GB) or anything that costs money (cloud GPUs, paid APIs).
- Pin tool versions (`mise.toml`) once a tool is chosen.

## Notes

- Notes live in `FAQ.md`. When the user asks a question worth keeping (concepts, decisions and their why, gotchas), add it there without asking. Skip one-off questions (currency conversion, status checks).
- Write notes as a FAQ: `##` topics, `###` questions, short direct answers with the why. Commands where they belong.
- Record measured numbers (tokens/s, memory, latency, load time) with the model, quantization and runtime they came from. Mark estimates as estimates.
- Crisp: no URLs, no filler.
