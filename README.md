## How it works (mental model)

This workflow separates two different goals that would otherwise fight each other:

- Goal A: Keep a clean, reproducible copy of the upstream project so you can run upstream examples and verify upstream behavior.
- Goal B: Maintain your own evolving work (scripts/notebooks/configs) without being constantly disrupted by upstream changes.

To achieve this, the repo uses two branches in the same folder:

- `main` = upstream mirror branch (disposable)
- `work` = your personal work branch (persistent)

When you switch branches (`git checkout main` vs `git checkout work`), the files in the same directory change. This is normal: the folder always reflects the commit that the current branch points to.

### What is HEAD?

`HEAD` is Git’s "you are here" pointer.

- If `HEAD` points to `work`, your working directory shows the current state of branch `work`.
- If `HEAD` points to `main`, your working directory shows the current state of branch `main`.

You can always check where you are with `git status` (it prints `On branch ...`).

### Local vs remote

You usually have two remotes:

- `origin`: your fork (read/write)
- `upstream`: the author repo (read-only)

Remote-tracking names like `origin/work` or `upstream/main` are *local references* to what Git last saw on those remotes after a `git fetch`.

### Why `main` is mirrored with reset (not merge)

This workflow treats `main` as a pure mirror of the author’s branch.

Mirroring means: local `main` should become *exactly identical* to `upstream/main`.

That is why the mirror step uses:

- `git reset --hard upstream/main`

This does not "combine histories" like merge. It simply moves `main` to the same commit as upstream and makes the files match upstream exactly.

Because your GitHub fork also mirrors `main`, the workflow pushes it using:

- `git push --force-with-lease origin main`

`--force-with-lease` is safer than `--force`: it refuses to overwrite the remote if the remote has unexpected new commits.

### Why your work is on a separate branch

Your own work lives on `work`, so:

- upstream updates do not overwrite your work
- your scripts/notebooks can evolve independently
- conflicts are minimized (especially if you mostly add new files instead of editing upstream core files)

### What each action achieves conceptually

BEGIN:
- Synchronize your personal work from `origin/work` (useful when you work on multiple machines).
- Update `main` to match upstream exactly (so you can run upstream behavior cleanly).
- Optionally update the conda environment if YAML changed.

MERGE:
- Take upstream updates (already mirrored into `main`) and bring them into `work`.
- Before merging, the workflow creates a timestamped backup branch so you can rollback easily.

END:
- Save your current work state by committing and pushing `work` to `origin/work`.
- This is primarily for backup and cross-machine sync.

### What causes merge conflicts in this workflow?

Conflicts usually occur only when both sides edit the same lines in the same file:

- you changed an upstream file in `work`
- upstream changed the same region
- you merge `main` into `work`

If you mostly keep your work in separate folders (e.g. `scripts/`, `notebooks/`, `my_project/`), conflicts are rare.

### Rollback principle

Before merging upstream into `work`, a backup branch is created:

- `backup/work-YYYYMMDD-HHMMSS`

If the merge causes problems, you can reset `work` back to that backup and force-update your fork’s `work` branch (single-user scenario).











## One-time setup per target project

### 1) Fork and clone

Fork the upstream repo to your GitHub account, then clone your fork:

~~~bat
git clone https://github.com/<you>/<repo>.git
cd <repo>
~~~

### 2) Add upstream

~~~bat
git remote add upstream https://github.com/<author>/<repo>.git
git remote -v
~~~

You should see both `origin` and `upstream`.

### 3) Create work branch

~~~bat
git checkout main
git checkout -b work
git push -u origin work
~~~

### 4) Create the conda environment (if the project provides it)

If the project has `environment.yml`:

~~~bat
conda env create -f environment.yml
~~~

(or `env.yml`)

---

## Installing the manager

Place the manager `.bat` file (e.g. `repo_manager.bat`) anywhere you want:

- inside the target repo root, OR
- in a personal tools folder.

Edit these variables at the top of the `.bat`:

~~~bat
set "REPO_DIR=C:\Users\%USERNAME%\OneDrive\Projects\repo"
set "ENV_NAME=my_env"
~~~

- `REPO_DIR` must point to the target repo directory.
- `ENV_NAME` must be the conda environment name used by that repo.

---

## Usage

### Interactive menu (double-click)

Double-click the `.bat` and choose:

- B = BEGIN
- M = MERGE
- E = END
- Q = quit

Recommended daily flow:

1. Run BEGIN when you start
2. Run MERGE when you want upstream updates in `work`
3. Run END before leaving

### Direct mode (optional)

If your script supports calling labels via arguments, you can run:

~~~bat
repo_manager.bat BEGIN
repo_manager.bat MERGE
repo_manager.bat ENDOP
~~~

(Use the action name that matches your script.)

---

## Mirror policy warning (main is disposable)

`main` is treated as a pure mirror of upstream:

- local `main` is reset to `upstream/main`
- `origin/main` is force-updated to match upstream

Do not put personal work on `main`. Use `work`.

---

## Rollback / undo (MERGE safety)

MERGE creates a backup branch like:

~~~text
backup/work-YYYYMMDD-HHMMSS
~~~

To revert `work` to a backup:

~~~bat
git checkout work
git reset --hard backup/work-YYYYMMDD-HHMMSS
git push --force-with-lease origin work
~~~

This is appropriate for a single-user fork.

---

## Conflicts (what to expect)

A conflict occurs when both sides changed the same lines in the same file.

Typical scenario:

- you modified an upstream file in `work`
- upstream also modified that same section
- you MERGE `main` into `work`

If a merge conflict happens:

1. Resolve conflicts in VS Code (or any editor)
2. Then:

~~~bat
git add .
git commit
git push origin work
~~~

To abort a merge:

~~~bat
git merge --abort
~~~

---

## About “push on close / shutdown”

A batch script cannot reliably run cleanup logic when:

- the console window is force-closed
- the machine shuts down abruptly
- power is lost

So guaranteed “push on close/shutdown” is not possible in pure batch.

Recommended practice:

- run END explicitly before leaving
- commit/push frequently (small commits)
- rely on MERGE backups for safe rollback

Optional improvement (works on normal exit, not forced close): a wrapper that runs BEGIN, opens a working shell, then runs END after you type `exit`:

~~~bat
@echo off
call repo_manager.bat BEGIN || exit /b 1
cmd /k
call repo_manager.bat ENDOP
~~~

---

## Suggested layout for work

To minimize conflicts, keep personal additions under dedicated folders:

~~~text
scripts/
notebooks/
configs/
my_project/
~~~

Avoid editing upstream core files unless necessary.

---

## License

Choose a license that fits your usage (MIT is common for small tooling).
