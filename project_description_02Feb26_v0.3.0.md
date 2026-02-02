# Anaconda Workflow Manager (Windows Batch) — Updated Spec (Handoff)

**Baseline:** V0.2.0 @ `45abc4c`  
This spec corrects the earlier handoff by aligning it with the issues discovered in the current code (especially control-flow in `ENDOP` / `MERGE` when called from `SESSION`).

---

## 0) Purpose

A single `repo_manager.bat` that you can drop into a Git repo to manage:

- Git sync (simple repo or fork + upstream repo)
- Optional conda activation + env update from YAML
- Optional VS Code open
- A single-window *session loop* so you can type commands and exit safely with `save` / `exit`

The file is intended to be **vendored per project**: if it works, it stays static.

---

## 1) Hard requirements

### 1.1 Single-window only
- No nested `cmd /k`
- No spawning a second terminal for the manager
- No self-relaunch via `%TEMP%`

### 1.2 Default action = SESSION
- Running `repo_manager.bat` with no args must run **BEGIN once**, then enter a command loop.

### 1.3 Two repo types

#### A) Simple repo (no `upstream` remote)
- Only `origin` exists
- Use local `main` as the working branch
- Do **bidirectional sync** between local `main` and `origin/main`
  - local ahead → (if dirty: commit/stash/abort) → push
  - remote ahead → pull `--rebase`
  - diverged → prompt: Abort / Rebase+push / Force-with-lease push

#### B) Fork + upstream repo (`origin` + `upstream`)
Strict policy:

- `main` = **pure mirror** of upstream default branch  
  Never do personal work on `main`.
- `work` = your working branch (you live here)

BEGIN must:
- Mirror `upstream/<default>` → local `main` **without checking out `main`**
- Force-with-lease push that mirror to `origin/main`
- Pull/rebase `work` from `origin/work`

MERGE is explicit and optional (never automatic): merge mirrored `main` into `work` with a backup branch for rollback.

### 1.4 Robust under university Windows constraints
- Quiet conda detection (avoid noisy “cannot find file” spam)
- Avoid temp relaunch tricks

### 1.5 Conda integration (optional)
If `ENV_NAME` is configured:

- Detect `conda.bat` quietly (best effort)
- Activate env (best effort)
- If `environment.yml` or `env.yml` exists, run:
  - `conda env update -n <ENV_NAME> -f <yaml> --prune`

### 1.6 Session command loop
Commands:

- `help`, `status`, `begin`, `merge`, `menu`, `save`, `exit`

Parsing rules (must hold):

- Accept leading/trailing spaces
- Accept surrounding quotes
- Use **first token only** for dispatch

These must work:

- `exit`
- `exit   `
- `"exit"`
- `"exit"   `
- `exit now`

### 1.7 Accepted limitation
If user closes the window with **X**, the manager cannot run END. Safe workflow is always: type `save` / `exit`.

---

## 2) Vendoring & branch placement

### 2.1 Simple repos
- `repo_manager.bat` may live in repo root on `main`.

### 2.2 Fork + upstream repos (strict mirror)
- Do **not** track `repo_manager.bat` on `main` (since `main` is mirrored)
- Track it on `work` only
- It can still be placed in repo root; it simply won’t exist when `main` is checked out (expected).

Rollback is already provided by Git history. (Tags are optional, not required.)

---

## 3) Branch automation rules (fork + upstream)

If `origin/work` does not exist, the manager may create it automatically:

- Base = `origin/main` if it exists, otherwise `origin/HEAD`
- Create local `work` from base
- Push `work` to origin with upstream tracking (`-u`)

This automation must fail clearly if it cannot identify a safe base.

---

## 4) Behavior contract (commands)

### 4.1 SETUP (internal)
Validate:

- Inside a Git repo
- `origin` exists
- Determine `HAS_UPSTREAM` from `upstream` remote existence

Fetch:

- `git fetch origin --prune`
- If upstream exists: `git fetch upstream --prune`

Determine default branches:

- `ORIGIN_HEAD` from `refs/remotes/origin/HEAD` (fallback `main`)
- `UPSTREAM_HEAD` from `refs/remotes/upstream/HEAD` (fallback `main`)

Detect conda quietly (optional).

---

### 4.2 BEGIN

#### A) Simple repo (no upstream)
1. Checkout/create local `main` from `origin/HEAD`
2. If dirty: prompt **Commit / Stash / Abort**
3. Fetch origin again
4. Compute ahead/behind: `origin/main...main`
5. Resolve:
   - ahead only → push
   - behind only → pull `--rebase`
   - diverged → prompt:
     - Abort
     - Rebase onto origin then push
     - Force-with-lease push local
6. Optional conda env update
7. Optional open VS Code

#### B) Fork + upstream
All work happens on `work` (never check out `main`).

1. Ensure `work` exists (auto-create/push if missing)
2. Checkout `work`
3. If dirty on `work`: warn + Continue/Abort (no auto-stash by default)
4. Mirror upstream default into local `main` **without checkout**:
   - `git branch -f main upstream/<UPSTREAM_HEAD>`
   - `git push --force-with-lease origin main`
5. Pull/rebase `work`:
   - `git pull --rebase origin work`
6. Optional conda env update
7. Optional open VS Code

---

### 4.3 MERGE (fork + upstream only)
MERGE is explicit; never automatic.

1. Checkout `work`
2. Pull --rebase: `origin/work`
3. Mirror upstream → main again (same mirror step as BEGIN)
4. Create backup branch from current `work`:
   - `backup/work-YYYYMMDD-HHMMSS`
   - Push backup to origin
5. Merge `main` into `work`
   - If conflict: stop and instruct manual resolution; backup remains available
6. If merge succeeds: push `work` to origin

---

### 4.4 END (save)
END always operates on the “effective work branch”:

- fork + upstream → `work`
- simple repo → `main`

Steps:

1. Checkout effective branch
2. If dirty: prompt commit message (default `wip`), then `git add -A` and commit
3. Push to origin
4. Return success/failure to caller

---

### 4.5 SESSION (default)
1. Run BEGIN once
2. Enter command loop:
   - `help`: show help
   - `status`: `git status -sb`
   - `begin`: run BEGIN again
   - `merge`: run MERGE (only if upstream exists)
   - `menu`: enter MENU UI
   - `save` / `exit`: run END, then terminate the script

Parsing rules:

- Trim leading + trailing spaces
- Strip surrounding quotes
- Dispatch only first token

---

## 5) Control-flow rules (critical)

To avoid the discovered bugs, the implementation must obey:

1. **Operation labels return:** `BEGIN`, `MERGE`, `END` must finish with `exit /b <code>`  
   They must **not** `goto MENU` internally.

2. **MENU is a controller:** MENU may call operations (`call :BEGIN`, etc.) and then decide whether to pause/loop/exit.

3. **SESSION is a controller:** SESSION must not drop into MENU unless user explicitly types `menu`.

Consequence: `save/exit` in SESSION correctly terminates the script after END completes.

---

## 6) Error handling & pause policy

- In SESSION: avoid forced `pause` after normal operations
- In MENU: it’s acceptable to pause after operations (double-click friendly)
- Fatal errors: print clear message, return nonzero; MENU may pause, SESSION may keep loop or abort depending on where it fails

---

## 7) Configuration knobs (top of file)

Required:

- `REPO_DIR` empty → use bat directory
- `ENV_NAME` empty → conda disabled
- `MAIN_BRANCH=main`
- `WORK_BRANCH=work`
- `AUTO_OPEN_CODE=1|0`

Optional future knobs (not required now, but spec-friendly):

- `PAUSE_IN_MENU=1|0`
- `ALLOW_FORCE_PUSH_SIMPLE=1|0`

---

## 8) Known limitations (accepted)

- Closing the window bypasses END
- Merge conflicts require manual resolution
- Upstream mirroring may fail if `origin/main` has unexpected commits and `--force-with-lease` rejects (this is desirable safety)
