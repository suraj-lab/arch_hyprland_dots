---
name: git
description: General Git workflow for inspecting, staging, committing, and pushing repository changes
---
# Git Skill

## Rules
- Confirm the repository before acting.
- Inspect status and diff before staging or committing.
- Make atomic commits: one logical change per commit.
- Do not commit unrelated changes together.
- Do not discard, reset, clean, rebase, or force-push unless explicitly requested.
- Ask before committing.
- Ask again before pushing.

## Commit Workflow
1. Confirm repo and branch:
   ```bash
   git rev-parse --show-toplevel
   git branch --show-current
   ```

2. Inspect changes:
   ```bash
   git status --short
   git diff --stat
   git diff
   ```

3. Summarize:
   - files changed
   - what changed
   - risk or notable details
   - suggested verification

4. Suggest **3 commit message detail levels** for the user to choose from.
   The user prefers detail, so default to offering more informative messages rather than terse ones.

   Provide options in this shape:

   ```text
   Option 1 — concise
   type(scope): short summary

   Option 2 — detailed subject
   type(scope): more descriptive summary with the key change/context

   Option 3 — full commit message
   type(scope): detailed subject

   - What changed
   - Why it changed
   - Any verification, migration, or follow-up notes
   ```

   Guidance:
   - Prefer Conventional Commit style when it fits.
   - Use a body for non-trivial changes.
   - Make Option 3 the recommended/default choice unless the user asks for brevity.
   - If multiple logical changes exist, propose separate commits instead of one broad message.

5. Wait for the user to choose/approve a commit message.

6. Stage explicit files:
   ```bash
   git add <file>
   ```

7. Commit:
   ```bash
   git commit -m "type: description"
   ```

8. Show result:
   ```bash
   git status
   git log --oneline -1
   ```

9. Push only after explicit confirmation:
   ```bash
   git push
   ```

## Commit Message Types
```text
feat: new capability
fix: bug fix
refactor: restructure without behavior change
chore: maintenance
docs: documentation
test: tests
style: formatting only
perf: performance
build: build/dependency changes
ci: CI changes
```

## Destructive Commands Need Explicit Confirmation
Do not run these unless the user clearly requests them and confirms the target:

```bash
git reset
git reset --hard
git restore
git checkout -- <file>
git clean
git rebase
git push --force
git push --force-with-lease
git branch -D
git tag -d
```
