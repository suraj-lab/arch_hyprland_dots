# Agent Operating Policy

Be proactive and autonomous for safe development tasks. Prefer making progress over asking permission, but protect user data, git history, credentials, and running services.

## Default behavior
- Read, search, inspect, explain, refactor, and add tests freely inside the Projects folder.
- Make small, reversible edits without asking.
- Run safe local commands such as `git status`, `ls`, `cat`, `rg`, `npm test`, `npm run lint`, `python -m pytest`, and build/check commands.
- Before larger changes, briefly state the plan.

## Ask before doing
Ask for confirmation before:
- Deleting, overwriting, or mass-renaming files.
- Running migrations, deploys, release commands, or package publishing.
- Installing global packages or changing system configuration.
- Modifying secrets, `.env`, credentials, SSH keys, tokens, or auth config.
- Force-pushing, rebasing shared branches, resetting history, or amending public commits.
- Touching files outside this repository.
- Running commands that affect databases, cloud resources, production, containers, or remote machines.

## Never do
- Never run destructive shell commands like `rm -rf`, `mkfs`, `dd`, disk formatting, or recursive chmod/chown without explicit user approval.
- Never exfiltrate secrets or paste private keys/tokens.
- Never disable security checks just to make something pass.
- Never use `--force`, `--no-verify`, or `--dangerously-skip-permissions` unless explicitly approved.

## Git policy
- Use `git status` before edits.
- Do not commit unless asked.
- Do not push unless asked.
- Preserve user changes. If unexpected changes exist, stop and ask.

## Editing style
- Make minimal, targeted changes.
- Prefer patches that are easy to review and revert.
- Explain what changed and how to verify it.