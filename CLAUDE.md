# fde-lab

A personal lab for forward deployed engineer (FDE) skills: taking models and AI systems into a customer's environment and making them work there.

## Scope

- Deployment first: running and serving models, locally and then on cloud infra. Development (building on top of models) comes later.
- Separate from `../gke-lab` by choice. Reuse what it teaches; don't merge them.
- Scope beyond that isn't set. The user sets the direction and designs the lab; propose options, don't pick them.

## Machine

- Apple M5, 16 GB unified memory, about 175 GB free disk (2026-11-15).
- 16 GB caps what runs locally. State a model's size and quantization before pulling it, and check it fits with headroom.

## Workflow

- Commit after every meaningful change (a finished, working step), without waiting to be asked. Stage files by name.
- Scratch space is `tmp/` in this repo (gitignored), not the system temp dir.
- Model weights stay out of git: `models/` and weight files are gitignored.
- Ask before large downloads (several GB) or anything that costs money (cloud GPUs, paid APIs).
- Pin tool versions (`mise.toml`) once a tool is chosen.

## Notes

- Write notes as a FAQ: `##` topics, `###` questions, short direct answers with the why. Commands where they belong.
- Record measured numbers (tokens/s, memory, latency, load time) with the model, quantization and runtime they came from. Mark estimates as estimates.
- Crisp: no URLs, no filler.
