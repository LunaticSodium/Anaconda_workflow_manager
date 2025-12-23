Below is a **single, self-contained handoff document** you can paste into a new chat after Christmas. It includes: your goals, project structure, workflow rules, branch/remotes strategy, and a **complete `repo_manager.bat` (single-window, bidirectional sync for simple repos, upstream mirroring for fork+upstream repos, and a built-in “text manager” command loop)**. It also documents every function/label and the expected behavior.

---

# Anaconda Workflow Manager (Windows Batch) — Handoff Doc

## 0) What you wanted (requirements)

You want a **single `.bat` file** you can drop into any Git repo to act as a **click-to-sync manager** for conda + Git.

### Your key demands

1. **Single window only** while running (no nested `cmd /k`, no “new terminal session” for the manager).

2. **Automatic sync when you click it** (default action = session mode).

3. Supports two repo types:

   **A) “Simple repo”** (no `upstream` remote; e.g., the manager’s own repo)

   * Do **bidirectional sync** between local `main` and `origin/main`:

     * If local is newer → **commit (if dirty) then push**
     * If remote is newer → pull/rebase
     * If diverged → prompt for what to do

   **B) “Fork + upstream repo”** (has both `origin` and `upstream`)

   * Maintain a strict policy:

     * `main` = **pure mirror** of upstream (never put personal work there)
     * `work` = **your own branch**
   * On start: auto **mirror upstream → main** (force, but **without checking out `main`**) to avoid script self-destruct.
   * Then sync `work` from `origin/work`.
   * Optional merge: merge mirrored `main` into `work` with a rollback backup branch.

4. Keep it robust under university Windows constraints (avoid `%TEMP%` self-relaunch).

5. Conda integration:

   * Optional: activate env name you set.
   * Optional: update env from `environment.yml` or `env.yml` if present.
   * Conda detection should be **quiet and explicit** (no “The system cannot find the file specified.” noise).

6. Provide a **text-manager style command loop** in session mode:

   * `help`, `status`, `begin`, `merge`, `menu`, `save`, `exit` (exit = save)
   * `exit` must work even if you type extra spaces or quotes.

7. You were okay with the limitation:

   * **Cannot auto-push if you close the window with X or shutdown**. The safe workflow is: type `save`/`exit`.

---

## 1) Recommended project structure and branch policy

### For fork+upstream repos

* Remotes:

  * `origin`  = your fork (you push here)
  * `upstream` = original author repo (you fetch from here)
* Branches:

  * `main` = **mirror** of `upstream/<default>` (force-updated)
  * `work` = your work / experiments / notebooks / scripts (the branch you live on)

### For conflict minimization

Keep personal additions in dedicated folders, e.g.

```
scripts/
notebooks/
configs/
my_project/
```

Avoid editing upstream core files unless necessary.

---

## 2) Core workflow (“manager behavior”)

### BEGIN

* If **no upstream**:

  * Works on `main` only.
  * If working tree dirty → prompt: Commit / Stash / Abort.
  * Fetch origin and compare `main` vs `origin/main`:

    * ahead only → push
    * behind only → pull --rebase
    * diverged → prompt (Abort / Rebase+push / Force-push)
* If **has upstream**:

  * Works on `work` branch in the working tree.
  * Mirror upstream default branch into local `main` **without checking out `main`**:

    * `git branch -f main upstream/<default>`
    * `git push --force-with-lease origin main`
  * Pull `work` from origin with rebase.
  * Optional: update conda env if YAML present.
  * Optional: open VS Code without spawning extra cmd window.

### MERGE (only when upstream exists)

* Update `work` from origin first (pull --rebase)
* Ensure mirrored `main` is up to date from upstream
* Create backup branch:

  * `backup/work-YYYYMMDD-HHMMSS` pushed to origin
* Merge `main` into `work`

  * On conflict: stop and tell you to resolve in editor; backup remains for rollback.

### END (save)

* On effective work branch:

  * If dirty → ask for commit message (default `wip`) and commit.
  * Push to origin.

### SESSION (default when you run without args)

* Runs BEGIN once
* Then stays in **the same prompt** with a loop:

  * `help`, `status`, `begin`, `merge`, `menu`, `save`, `exit`
* `save` and `exit` do END and then close the manager.

---

## 3) The final `repo_manager.bat` (full file)

> Put this file in the repo root.
> Run it from PowerShell or Anaconda Prompt as `.\repo_manager.bat` or just double-click.

```bat
@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =========================
:: CONFIG
:: =========================
:: Put this file in the repo root. Leave REPO_DIR empty to use the .bat directory.
set "REPO_DIR="
:: Optional: set to a conda env name, e.g. BTO_ML. Leave empty to disable conda actions.
set "ENV_NAME="

set "MAIN_BRANCH=main"
set "WORK_BRANCH=work"

:: Open VS Code automatically after BEGIN (1=yes, 0=no)
set "AUTO_OPEN_CODE=1"

:: =========================
:: DEFAULT: no args -> SESSION
:: =========================
if "%~1"=="" goto SESSION
if /i "%~1"=="SESSION" goto SESSION
if /i "%~1"=="BEGIN" goto BEGIN
if /i "%~1"=="MERGE" goto MERGE
if /i "%~1"=="END" goto ENDOP
if /i "%~1"=="MENU" goto MENU
goto MENU

:HELP
echo.
echo ======================================================
echo  Repo Manager (single-window)
echo ======================================================
echo  Default: SESSION  (sync now, then command loop)
echo.
echo  Commands in SESSION:
echo    help     - show help
echo    status   - git status -sb
echo    begin    - run BEGIN sync again
echo    merge    - run MERGE (only if upstream exists)
echo    menu     - go to menu
echo    save     - commit/push and exit
echo    exit     - same as save
echo ======================================================
echo.
exit /b 0

:MENU
cls
call :HELP
echo  [S] SESSION  - sync + stay in same window (type save/exit to push)
echo  [B] BEGIN    - sync now
echo  [M] MERGE    - backup + merge main->work (needs upstream)
echo  [E] END      - commit/push now
echo  [Q] Quit
echo.
choice /c SBMEQ /n /m "Select Action: "
if errorlevel 5 exit /b 0
if errorlevel 4 goto ENDOP
if errorlevel 3 goto MERGE
if errorlevel 2 goto BEGIN
if errorlevel 1 goto SESSION
goto MENU

:: =========================
:: SETUP
:: =========================
:SETUP
if not defined REPO_DIR set "REPO_DIR=%~dp0"
cd /d "%REPO_DIR%" || (echo ERROR: cannot cd to "%REPO_DIR%" & pause & exit /b 1)

where git >nul 2>nul || (echo ERROR: git not found in PATH & pause & exit /b 1)
git rev-parse --is-inside-work-tree >nul 2>nul || (echo ERROR: not a git repo & pause & exit /b 1)

git remote get-url origin >nul 2>nul || (echo ERROR: 'origin' remote not found & pause & exit /b 1)

set "HAS_UPSTREAM=0"
git remote get-url upstream >nul 2>nul && set "HAS_UPSTREAM=1"

git fetch origin --prune >nul 2>nul

set "ORIGIN_HEAD=%MAIN_BRANCH%"
for /f "delims=" %%R in ('git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2^>nul') do set "ORIGIN_HEAD=%%R"
if defined ORIGIN_HEAD set "ORIGIN_HEAD=!ORIGIN_HEAD:origin/=!"

set "UPSTREAM_HEAD=%MAIN_BRANCH%"
if "%HAS_UPSTREAM%"=="1" (
  git fetch upstream --prune >nul 2>nul
  git remote set-head upstream -a >nul 2>nul
  for /f "delims=" %%R in ('git symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2^>nul') do set "UPSTREAM_HEAD=%%R"
  if defined UPSTREAM_HEAD set "UPSTREAM_HEAD=!UPSTREAM_HEAD:upstream/=!"
)

call :FIND_CONDA_SILENT
exit /b 0

:: =========================
:: CONDA (silent detection; no noisy probing)
:: =========================
:FIND_CONDA_SILENT
set "CONDA_BAT="
set "CONDA_STATUS=missing"

:: 1) If launched from conda prompt, CONDA_PREFIX is usually set
if defined CONDA_PREFIX (
  if exist "%CONDA_PREFIX%\condabin\conda.bat" set "CONDA_BAT=%CONDA_PREFIX%\condabin\conda.bat"
)

:: 2) If CONDA_EXE is set, infer base = parent of Scripts\
if not defined CONDA_BAT if defined CONDA_EXE (
  if exist "%CONDA_EXE%" (
    for %%I in ("%CONDA_EXE%") do set "CE_DIR=%%~dpI"
    for %%I in ("!CE_DIR!\..") do set "CE_BASE=%%~fI"
    if exist "!CE_BASE!\condabin\conda.bat" set "CONDA_BAT=!CE_BASE!\condabin\conda.bat"
  )
)

:: 3) Common install locations
if not defined CONDA_BAT (
  for %%A in (
    "%USERPROFILE%\anaconda3\condabin\conda.bat"
    "%USERPROFILE%\miniconda3\condabin\conda.bat"
    "C:\ProgramData\anaconda3\condabin\conda.bat"
    "C:\ProgramData\miniconda3\condabin\conda.bat"
  ) do if exist "%%~A" set "CONDA_BAT=%%~A"
)

if defined CONDA_BAT set "CONDA_STATUS=ok"
exit /b 0

:CONDA_ACTIVATE
if "%ENV_NAME%"=="" exit /b 0
if not "%CONDA_STATUS%"=="ok" (
  echo INFO: conda not detected (skip activate %ENV_NAME%)
  exit /b 0
)
call "%CONDA_BAT%" activate "%ENV_NAME%" >nul 2>nul
if errorlevel 1 echo WARN: conda activate failed for %ENV_NAME%
exit /b 0

:CONDA_ENV_UPDATE
if "%ENV_NAME%"=="" exit /b 0
if not "%CONDA_STATUS%"=="ok" exit /b 0
if exist environment.yml (
  call "%CONDA_BAT%" env update -n "%ENV_NAME%" -f environment.yml --prune >nul
  exit /b 0
)
if exist env.yml (
  call "%CONDA_BAT%" env update -n "%ENV_NAME%" -f env.yml --prune >nul
  exit /b 0
)
exit /b 0

:: =========================
:: VS CODE (avoid spawning extra cmd window)
:: =========================
:OPEN_CODE
if "%AUTO_OPEN_CODE%"=="1" (
  set "VSCODE_EXE="
  if exist "%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe" set "VSCODE_EXE=%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe"
  if exist "%ProgramFiles%\Microsoft VS Code\Code.exe" set "VSCODE_EXE=%ProgramFiles%\Microsoft VS Code\Code.exe"

  if defined VSCODE_EXE (
    start "" /b "%VSCODE_EXE%" . >nul 2>nul
  ) else (
    where code >nul 2>nul
    if not errorlevel 1 start "" /b code . >nul 2>nul
  )
)
exit /b 0

:: =========================
:: GIT HELPERS
:: =========================
:CHECKOUT_OR_CREATE
:: %1=branch  %2=startpoint
git show-ref --verify --quiet refs/heads/%~1
if errorlevel 1 (
  if "%~2"=="" exit /b 1
  git checkout -B %~1 %~2 >nul 2>nul
  exit /b %ERRORLEVEL%
)
git checkout %~1 >nul 2>nul
exit /b %ERRORLEVEL%

:ENSURE_WORK
set "WORK_EFF=%WORK_BRANCH%"

if "%HAS_UPSTREAM%"=="0" (
  set "WORK_EFF=%MAIN_BRANCH%"
  exit /b 0
)

git show-ref --verify --quiet refs/remotes/origin/%WORK_BRANCH% >nul 2>nul
if not errorlevel 1 exit /b 0

echo INFO: origin/%WORK_BRANCH% not found; creating it from origin/%MAIN_BRANCH% (or origin/%ORIGIN_HEAD%)
git show-ref --verify --quiet refs/remotes/origin/%MAIN_BRANCH% >nul 2>nul
if errorlevel 1 (set "BASE=origin/%ORIGIN_HEAD%") else (set "BASE=origin/%MAIN_BRANCH%")
call :CHECKOUT_OR_CREATE %WORK_BRANCH% %BASE% || exit /b 1
git push -u origin %WORK_BRANCH% >nul 2>nul || exit /b 1
exit /b 0

:DIRTY_PROMPT_SIMPLE
git status --porcelain | findstr . >nul
if errorlevel 1 exit /b 0

echo.
echo WARNING: uncommitted changes:
git status --porcelain
echo.
choice /c CSA /n /m "Simple repo: [C] Commit  [S] Stash  [A] Abort: "
if errorlevel 3 exit /b 1
if errorlevel 2 (
  git stash push -u -m "repo_manager auto stash" || exit /b 1
  exit /b 0
)
call :AUTO_COMMIT || exit /b 1
exit /b 0

:AUTO_COMMIT
setlocal DisableDelayedExpansion
set "MSG="
set /p "MSG=Commit message (empty=wip): "
if not defined MSG set "MSG=wip"
set "MSG=%MSG:"='%" 
endlocal & set "MSG=%MSG%"

git add -A || exit /b 1
git commit -m "%MSG%" || exit /b 1
exit /b 0

:: =========================
:: UPSTREAM MIRROR (no checkout main)
:: =========================
:MIRROR_UPSTREAM_TO_MAIN
if "%HAS_UPSTREAM%"=="0" exit /b 0
echo.
echo --- Mirror upstream/%UPSTREAM_HEAD% -> %MAIN_BRANCH% (no checkout) ---
git fetch upstream --prune || exit /b 1
git show-ref --verify --quiet refs/remotes/upstream/%UPSTREAM_HEAD% || exit /b 1
git branch -f %MAIN_BRANCH% upstream/%UPSTREAM_HEAD% >nul 2>nul || exit /b 1
git push --force-with-lease origin %MAIN_BRANCH% >nul 2>nul || exit /b 1
exit /b 0

:: =========================
:: SIMPLE REPO BIDIRECTIONAL SYNC
:: =========================
:SYNC_SIMPLE_BIDIR_MAIN
echo.
echo --- Simple sync (no upstream): %MAIN_BRANCH% <-> origin/%MAIN_BRANCH% ---
git fetch origin --prune || exit /b 1

call :CHECKOUT_OR_CREATE %MAIN_BRANCH% origin/%ORIGIN_HEAD% || exit /b 1
call :DIRTY_PROMPT_SIMPLE || exit /b 1

git fetch origin --prune || exit /b 1

set "BEHIND=0"
set "AHEAD=0"
for /f "tokens=1,2" %%a in ('git rev-list --left-right --count origin/%MAIN_BRANCH%...%MAIN_BRANCH% 2^>nul') do (
  set "BEHIND=%%a"
  set "AHEAD=%%b"
)

echo INFO: ahead=%AHEAD% behind=%BEHIND%

if "%AHEAD%"=="0" if "%BEHIND%"=="0" exit /b 0

if not "%AHEAD%"=="0" if "%BEHIND%"=="0" (
  git push origin %MAIN_BRANCH% || exit /b 1
  exit /b 0
)

if "%AHEAD%"=="0" if not "%BEHIND%"=="0" (
  git pull --rebase origin %MAIN_BRANCH% || exit /b 1
  exit /b 0
)

echo.
echo WARNING: diverged (both local and remote have new commits).
choice /c ARF /n /m "[A] Abort  [R] Rebase onto origin then push  [F] Force-push local: "
if errorlevel 3 (
  git push --force-with-lease origin %MAIN_BRANCH% || exit /b 1
  exit /b 0
)
if errorlevel 2 (
  git pull --rebase origin %MAIN_BRANCH% || exit /b 1
  git push origin %MAIN_BRANCH% || exit /b 1
  exit /b 0
)
exit /b 1

:: =========================
:: COMMANDS
:: =========================
:BEGIN
call :SETUP || exit /b 1
call :CONDA_ACTIVATE
call :ENSURE_WORK || (echo ERROR: cannot ensure work & pause & exit /b 1)

if "%HAS_UPSTREAM%"=="0" (
  call :SYNC_SIMPLE_BIDIR_MAIN || (echo ERROR: simple sync failed & pause & exit /b 1)
) else (
  call :CHECKOUT_OR_CREATE %WORK_EFF% origin/%WORK_EFF% >nul 2>nul

  git status --porcelain | findstr . >nul
  if not errorlevel 1 (
    echo.
    echo WARNING: uncommitted changes on %WORK_EFF%.
    choice /c YN /n /m "Continue anyway (Y) Abort (N): "
    if errorlevel 2 (echo Aborted. & pause & exit /b 1)
  )

  call :MIRROR_UPSTREAM_TO_MAIN || (echo ERROR: mirror failed & pause & exit /b 1)

  echo.
  echo --- Pull work: %WORK_EFF% ---
  git fetch origin --prune >nul 2>nul
  git pull --rebase origin %WORK_EFF% || (echo ERROR: pull work failed & pause & exit /b 1)
)

call :CONDA_ENV_UPDATE
call :OPEN_CODE
exit /b 0

:MERGE
call :SETUP || exit /b 1
if "%HAS_UPSTREAM%"=="0" (
  echo INFO: no upstream remote; MERGE skipped.
  pause
  goto MENU
)

call :CONDA_ACTIVATE
call :ENSURE_WORK || (echo ERROR: cannot ensure work & pause & exit /b 1)

call :CHECKOUT_OR_CREATE %WORK_EFF% origin/%WORK_EFF% >nul 2>nul
git pull --rebase origin %WORK_EFF% || (echo ERROR: pull work failed & pause & exit /b 1)

call :MIRROR_UPSTREAM_TO_MAIN || (echo ERROR: mirror failed & pause & exit /b 1)

echo.
echo --- Create backup ---
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "TS=%%T"
set "BKP=backup/%WORK_EFF%-%TS%"
git branch "%BKP%" || (echo ERROR: backup create failed & pause & exit /b 1)
git push -u origin "%BKP%" || (echo ERROR: backup push failed & pause & exit /b 1)

echo.
echo --- Merge %MAIN_BRANCH% -> %WORK_EFF% ---
git merge %MAIN_BRANCH%
if errorlevel 1 (
  echo.
  echo MERGE CONFLICT.
  echo Resolve, then: git add . ^& git commit ^& git push origin %WORK_EFF%
  echo Or abort:      git merge --abort
  echo Backup: %BKP%
  pause
  exit /b 1
)

git push origin %WORK_EFF% || (echo ERROR: push failed & pause & exit /b 1)
echo OK: MERGE done. Backup: %BKP%
pause
goto MENU

:ENDOP
call :SETUP || exit /b 1
call :CONDA_ACTIVATE
call :ENSURE_WORK || exit /b 1

call :CHECKOUT_OR_CREATE %WORK_EFF% origin/%WORK_EFF% >nul 2>nul

git status --porcelain | findstr . >nul
if not errorlevel 1 call :AUTO_COMMIT || (echo ERROR: commit failed & pause & exit /b 1)

git push origin %WORK_EFF% || (echo ERROR: push failed & pause & exit /b 1)
echo OK: pushed %WORK_EFF% to origin.
pause
goto MENU

:SESSION
call :BEGIN || exit /b 1
echo.
echo --- SESSION (same window) ---
echo Type "help" for commands. Type "save" or "exit" to commit/push and close.
echo.

:SESSION_LOOP
set "LINE="
set /p "LINE=repo_manager> "

:: trim leading spaces
for /f "tokens=* delims= " %%A in ("!LINE!") do set "LINE=%%A"

:: strip surrounding quotes: "exit" -> exit
if defined LINE (
  if "!LINE:~0,1!"=="^"" if "!LINE:~-1!"=="^"" set "LINE=!LINE:~1,-1!"
)

:: first token only (so "exit now" works)
set "CMD="
for /f "tokens=1" %%A in ("!LINE!") do set "CMD=%%A"

if not defined CMD goto SESSION_LOOP

if /i "!CMD!"=="help"   (call :HELP & goto SESSION_LOOP)
if /i "!CMD!"=="status" (git status -sb & goto SESSION_LOOP)
if /i "!CMD!"=="begin"  (call :BEGIN & goto SESSION_LOOP)
if /i "!CMD!"=="merge"  (call :MERGE & goto SESSION_LOOP)
if /i "!CMD!"=="menu"   goto MENU

if /i "!CMD!"=="save"   (call :ENDOP & exit /b 0)
if /i "!CMD!"=="exit"   (call :ENDOP & exit /b 0)
if /i "!CMD!"=="quit"   (call :ENDOP & exit /b 0)
if /i "!CMD!"=="q"      (call :ENDOP & exit /b 0)

echo Unknown command: "!LINE!"  ^(type "help"^)
goto SESSION_LOOP
```

---

## 4) Descriptions of each function/label (what they do)

### UI / entry

* `:HELP` — Prints usage and SESSION commands.
* `:MENU` — Menu UI for interactive choice.
* `:SESSION` — Default behavior (single window). Runs `BEGIN` then enters command loop.
* `:SESSION_LOOP` — Reads a line, trims spaces/quotes, uses first token to dispatch commands.

### Setup and detection

* `:SETUP` — Validates repo, detects remotes, fetches origin/upstream, detects default branch heads.
* `:FIND_CONDA_SILENT` — Detects `conda.bat` using `CONDA_PREFIX`, `CONDA_EXE`, or common install paths. Quiet.
* `:CONDA_ACTIVATE` — Activates `ENV_NAME` if configured and conda detected.
* `:CONDA_ENV_UPDATE` — If `environment.yml` or `env.yml` exists, updates env with `--prune`.

### Editor launch

* `:OPEN_CODE` — Launches VS Code by calling `Code.exe` directly if possible; falls back to `code` wrapper; uses `/b` to avoid extra windows.

### Git utilities

* `:CHECKOUT_OR_CREATE branch startpoint` — Checks out branch; creates it from startpoint if missing.
* `:ENSURE_WORK` — Ensures `work` exists for upstream repos; for simple repos sets effective work to `main`.
* `:DIRTY_PROMPT_SIMPLE` — In simple repo: if dirty, prompt Commit/Stash/Abort.
* `:AUTO_COMMIT` — Commit all changes with message prompt (default `wip`).

### Sync strategies

* `:MIRROR_UPSTREAM_TO_MAIN` — Mirrors upstream head into local `main` without checking it out; force-pushes `origin/main`.
* `:SYNC_SIMPLE_BIDIR_MAIN` — Bidirectional sync for simple repos:

  * commit/stash if dirty
  * compute `ahead/behind` and choose push/pull
  * if diverged, prompt for resolution.

### Main commands

* `:BEGIN` — Runs the correct sync strategy depending on upstream existence; updates env; opens VS Code.
* `:MERGE` — For upstream repos only: update work, mirror main, make backup, merge main into work, push.
* `:ENDOP` — Commit/push changes on effective work branch.

---

## 5) Known limitations (accepted)

* If you close the window with **X**, the manager cannot run `ENDOP`.
* For safe behavior, always type `save` or `exit`.

---

## 6) Next steps after Christmas (how to continue)

1. Put `repo_manager.bat` into the **BTO simulator repo root**.
2. Set:

   * `ENV_NAME=BTO_ML` (or your actual env name)
3. Ensure remotes:

   * `origin` exists (your fork)
   * `upstream` exists (author)
4. Run `.\repo_manager.bat` (or double-click).
5. If anything unexpected happens, copy the first ~30 lines of output into a new chat.

---
