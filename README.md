# Anaconda Workflow Manager (Windows Batch)

A single `repo_manager.bat` you drop into a repo root to manage:

- Git sync (simple repo OR fork+upstream mirror policy)
- Optional conda activation + env update (`environment.yml` / `env.yml`)
- Single-window interactive session (default)

---

## How it works (mental model)

This workflow separates two different goals that would otherwise fight each other:

- Goal A: Keep a clean, reproducible copy of the upstream project so you can run upstream examples and verify upstream behavior.
- Goal B: Maintain your own evolving work (scripts/notebooks/configs) without being constantly disrupted by upstream changes.

To achieve this, the repo uses two branches in the same folder:

- `main` = upstream mirror branch (disposable in fork+upstream repos)
- `work` = your personal work branch (persistent)

When you switch branches (`git checkout main` vs `git checkout work`), the files in the same directory change. This is normal: the folder always reflects the commit that the current branch points to.

### What is HEAD?

`HEAD` is Git’s "you are here" pointer.

- If `HEAD` points to `work`, your working directory shows branch `work`.
- If `HEAD` points to `main`, your working directory shows branch `main`.

Check where you are with `git status` (it prints `On branch ...`).

### Local vs remote

You usually have two remotes:

- `origin`: your fork (read/write)
- `upstream`: the author repo (read-only)

Remote-tracking names like `origin/work` or `upstream/main` are local references updated by `git fetch`.

### Why `main` is mirrored with reset (not merge)

This workflow treats `main` as a pure mirror of the author’s default branch.

Mirroring means: local `main` becomes exactly identical to `upstream/<default>`.

The manager enforces this by moving `main` to the upstream commit and pushing:

- `git push --force-with-lease origin main`

`--force-with-lease` is safer than `--force`: it refuses to overwrite the remote if it has unexpected new commits.

### Why your work is on a separate branch

Your own work lives on `work`, so:

- upstream updates do not overwrite your work
- your scripts/notebooks can evolve independently
- conflicts are minimized (especially if you mostly add new files instead of editing upstream core files)

### What each action achieves conceptually

**SYNC**:
- For simple repos: bidirectional sync between local `main` and `origin/<default>` (push/pull --rebase, and a prompt if diverged).
- For fork+upstream repos: mirror upstream into `main` (force-with-lease), then pull/rebase `work` from `origin/work`.
- Optionally activates conda and updates the env if YAML exists (when enabled in config).

**MERGE** (fork+upstream only):
- Take upstream updates (already mirrored into `main`) and bring them into `work`.
- Before merging, the workflow creates a timestamped backup branch so you can rollback easily.

**SAVE**:
- Save your current work state by committing and pushing the effective branch (`work` for upstream repos, `main` for simple repos).

### What causes merge conflicts in this workflow?

Conflicts happen when:

- you edited an upstream file in `work`, and
- upstream edited the same lines, and
- you merge `main` into `work`.

If you mostly keep your work in separate folders, conflicts are rare.

### Rollback principle

Before merging upstream into `work`, a backup branch is created:

- `backup/work-YYYYMMDD-HHMMSS`

If a merge causes problems, you can reset `work` back to that backup (and force-update `origin/work` if you are the only person using the fork).

---

## One-time setup per target project (fork+upstream case)

### 1) Fork and clone

```bat
git clone https://github.com/<you>/<repo>.git
cd <repo>
```

### 2) Add upstream

```bat
git remote add upstream https://github.com/<author>/<repo>.git
git remote -v
```

You should see both `origin` and `upstream`.

### 3) Create work branch (if you haven’t)

```bat
git checkout main
git checkout -b work
git push -u origin work
```

### 4) Create the conda environment (optional)

If the repo provides `environment.yml`:

```bat
conda env create -f environment.yml
```

(or `env.yml`)

---

## Installing the manager

Recommended: place `repo_manager.bat` in the **target repo root**.

Edit the config at the top of `repo_manager.bat` if needed:

```bat
set "REPO_DIR="
set "ENV_NAME=my_env"
```

- If `REPO_DIR` is empty, the script uses the folder where the `.bat` is located (recommended).
- Set `REPO_DIR` only if you keep the script elsewhere and want it to manage a different repo folder.
- `ENV_NAME` is the conda environment name for this repo (empty = disable conda actions).

Vendoring note for fork+upstream repos:
- `main` is overwritten by mirroring, so if you want this script tracked in Git, commit it on `work` (not on `main`).

---

## Usage

### Default (recommended): SESSION mode

Run (or double-click):

```bat
repo_manager.bat
```

It will:
1) sync once
2) stay in the same window with a prompt

SESSION commands:

- `help`   : show help
- `status` : `git status -sb`
- `sync`   : run sync again (alias: `begin`)
- `merge`  : backup + merge `main -> work` (only if upstream exists)
- `save`   : commit/push and exit
- `exit`   : same as `save`

Important: closing the window with **X** cannot run `save`. Always type `save` / `exit`.

### One-shot mode (no session)

```bat
repo_manager.bat help
repo_manager.bat sync
repo_manager.bat merge
repo_manager.bat save
```

---

## Mirror policy warning (main is disposable)

For fork+upstream repos, `main` is treated as a pure mirror of upstream:

- local `main` is reset to `upstream/<default>`
- `origin/main` is force-updated to match upstream

Do not put personal work on `main`. Use `work`.

---

## Rollback / undo (MERGE safety)

MERGE creates a backup branch like:

```text
backup/work-YYYYMMDD-HHMMSS
```

If a merge goes bad:

- reset `work` to the backup locally
- and (if needed) force-update `origin/work` back to that backup commit

---

## Conflicts (what to expect)

If conflicts occur during MERGE:

- resolve conflicts manually
- then: `git add .` → `git commit` → `git push origin work`

To abort a merge:

```bat
git merge --abort
```

---

## Suggested layout for your work

To minimize conflicts, keep personal additions under dedicated folders:

```text
scripts/
notebooks/
configs/
my_project/
```

Avoid editing upstream core files unless necessary.

---

## About “push on close / shutdown”

A batch script cannot reliably run cleanup logic when the window is closed by **X** or the machine shuts down.
Use `save` / `exit` to ensure changes are committed and pushed.

---

## Notes

- `LF will be replaced by CRLF` is normal on Windows; it’s Git line-ending normalization.
- If `git push` prompts for auth, that’s expected (credentials / SSO / PAT).
