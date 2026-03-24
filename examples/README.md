# Examples

Ready-to-use `iron-dome.yml` configurations for common scenarios.

| File | Use case |
|------|----------|
| [`minimal.yml`](minimal.yml) | Small projects — just secrets, conflicts, large files, branch policy |
| [`multi-agent.yml`](multi-agent.yml) | Repos with multiple AI agents — enables semaphore and orphan guard |
| [`ci-only.yml`](ci-only.yml) | Server-side scanning only, no local hooks |
| [`monorepo.yml`](monorepo.yml) | Large codebases — higher limits, more exclusions |

## Usage

```bash
# Copy the config to your repo
cp ~/.iron-dome/examples/multi-agent.yml ~/my-project/iron-dome.yml

# Install hooks
cd ~/my-project
iron-dome init
```

Customize after copying — every project is different.
