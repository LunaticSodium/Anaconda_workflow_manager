@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ======================================================
:: Repo Manager (single-window) — V0.2.1 (patched)
::
:: Default: SESSION  (sync once, then command loop)
:: One-shot:
::   repo_manager.bat sync
::   repo_manager.bat merge
::   repo_manager.bat save
::
:: Notes:
:: - For fork+upstream repos: keep this file on WORK branch (MAIN is mirrored).
:: - Closing the window (X) cannot run SAVE; use "save" / "exit".
:: ======================================================

:: =========================
:: CONFIG
:: =========================
:: Leave REPO_DIR empty to use the .bat directory.
set "REPO_DIR="
:: Optional: set conda env name (empty disables conda actions)
set "ENV_NAME="

set "MAIN_BRANCH=main"
set "WORK_BRANCH=work"

:: Open VS Code automatically after SYNC (1=yes, 0=no)
set "AUTO_OPEN_CODE=1"

:: Pause in one-shot mode (1=yes, 0=no)
set "PAUSE_ONESHOT=0"


:: =========================
:: ENTRY
:: =========================
set "ARG=%~1"
if "%ARG%"=="" goto SESSION

if /i "%ARG%"=="help"    goto HELP_PRINT
if /i "%ARG%"=="session" goto SESSION
if /i "%ARG%"=="sync"    goto ONESHOT_SYNC
if /i "%ARG%"=="begin"   goto ONESHOT_SYNC
if /i "%ARG%"=="merge"   goto ONESHOT_MERGE
if /i "%ARG%"=="save"    goto ONESHOT_SAVE
if /i "%ARG%"=="end"     goto ONESHOT_SAVE

echo ERROR: Unknown argument "%ARG%"
echo Try: repo_manager.bat help
exit /b 2


:HELP_PRINT
call :HELP
exit /b 0

:ONESHOT_SYNC
call :SYNC
set "RC=%ERRORLEVEL%"
if "%PAUSE_ONESHOT%"=="1" pause
exit /b %RC%

:ONESHOT_MERGE
call :MERGE
set "RC=%ERRORLEVEL%"
if "%PAUSE_ONESHOT%"=="1" pause
exit /b %RC%

:ONESHOT_SAVE
call :SAVE
set "RC=%ERRORLEVEL%"
if "%PAUSE_ONESHOT%"=="1" pause
exit /b %RC%


:HELP
echo.
echo ======================================================
echo  Repo Manager (single-window)
echo ======================================================
echo  Default: SESSION
echo.
echo  One-shot:
echo    repo_manager.bat sync     - sync now
echo    repo_manager.bat merge    - backup + merge main->work (needs upstream)
echo    repo_manager.bat save     - commit/push now
echo.
echo  SESSION commands:
echo    help     - show help
echo    status   - git status -sb
echo    sync     - run sync again   (alias: begin)
echo    merge    - merge main->work (only if upstream exists)
echo    save     - commit/push and exit
echo    exit     - same as save
echo ======================================================
echo.
exit /b 0


:: =========================
:: SETUP (avoid "( ... )" error handlers because paths may contain parentheses)
:: =========================
:SETUP
if not defined REPO_DIR set "REPO_DIR=%~dp0"

cd /d "%REPO_DIR%"
if errorlevel 1 goto SETUP_BADCD

where git >nul 2>nul
if errorlevel 1 goto SETUP_NOGIT

git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 goto SETUP_NOTGIT

git remote get-url origin >nul 2>nul
if errorlevel 1 goto SETUP_NOORIGIN

set "HAS_UPSTREAM=0"
git remote get-url upstream >nul 2>nul && set "HAS_UPSTREAM=1"

git fetch origin --prune >nul 2>nul
if errorlevel 1 goto SETUP_FETCHFAIL

:: origin default branch (fallback main)
set "ORIGIN_HEAD=%MAIN_BRANCH%"
for /f "delims=" %%R in ('git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2^>nul') do set "ORIGIN_HEAD=%%R"
if defined ORIGIN_HEAD set "ORIGIN_HEAD=!ORIGIN_HEAD:origin/=!"

:: what remote branch we consider "remote main" for sync
set "REMOTE_MAIN=%MAIN_BRANCH%"
git show-ref --verify --quiet refs/remotes/origin/%MAIN_BRANCH% >nul 2>nul
if errorlevel 1 set "REMOTE_MAIN=%ORIGIN_HEAD%"

:: upstream head if exists
set "UPSTREAM_HEAD=%MAIN_BRANCH%"
if "%HAS_UPSTREAM%"=="1" (
  git fetch upstream --prune >nul 2>nul
  git remote set-head upstream -a >nul 2>nul
  for /f "delims=" %%R in ('git symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2^>nul') do set "UPSTREAM_HEAD=%%R"
  if defined UPSTREAM_HEAD set "UPSTREAM_HEAD=!UPSTREAM_HEAD:upstream/=!"
)

call :FIND_CONDA_SILENT
exit /b 0

:SETUP_BADCD
echo ERROR: cannot cd to "%REPO_DIR%"
exit /b 1
:SETUP_NOGIT
echo ERROR: git not found in PATH
exit /b 1
:SETUP_NOTGIT
echo ERROR: not a git repo
exit /b 1
:SETUP_NOORIGIN
echo ERROR: 'origin' remote not found
exit /b 1
:SETUP_FETCHFAIL
echo ERROR: git fetch origin failed
exit /b 1


:: =========================
:: CONDA (silent detection; no noisy probing)
:: =========================
:FIND_CONDA_SILENT
set "CONDA_BAT="
set "CONDA_STATUS=missing"

:: 1) From conda prompt
if defined CONDA_PREFIX (
  if exist "%CONDA_PREFIX%\condabin\conda.bat" set "CONDA_BAT=%CONDA_PREFIX%\condabin\conda.bat"
)

:: 2) From CONDA_EXE
if not defined CONDA_BAT if defined CONDA_EXE (
  if exist "%CONDA_EXE%" (
    for %%I in ("%CONDA_EXE%") do set "CE_DIR=%%~dpI"
    for %%I in ("!CE_DIR!\..") do set "CE_BASE=%%~fI"
    if exist "!CE_BASE!\condabin\conda.bat" set "CONDA_BAT=!CE_BASE!\condabin\conda.bat"
  )
)

:: 3) Common locations
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
:: STRING HELPERS (SESSION parsing)
:: =========================
:TRIM_LINE
:: trims LINE leading/trailing spaces and strips surrounding quotes
for /f "tokens=* delims= " %%A in ("!LINE!") do set "LINE=%%A"
:TRIM_TAIL_LOOP
if not defined LINE exit /b 0
if "!LINE:~-1!"==" " (
  set "LINE=!LINE:~0,-1!"
  goto TRIM_TAIL_LOOP
)
if "!LINE:~0,1!"=="^"" if "!LINE:~-1!"=="^"" set "LINE=!LINE:~1,-1!"
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

echo INFO: origin/%WORK_BRANCH% not found; creating it from origin/%REMOTE_MAIN%
call :CHECKOUT_OR_CREATE %WORK_BRANCH% origin/%REMOTE_MAIN%
if errorlevel 1 exit /b 1
git push -u origin %WORK_BRANCH% >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

:IS_DIRTY
git status --porcelain | findstr . >nul
if errorlevel 1 exit /b 1
exit /b 0

:DIRTY_PROMPT_SIMPLE
call :IS_DIRTY
if errorlevel 1 exit /b 0

echo.
echo WARNING: uncommitted changes:
git status --porcelain
echo.
choice /c CSA /n /m "Simple repo: [C] Commit  [S] Stash  [A] Abort: "
if errorlevel 3 exit /b 1
if errorlevel 2 (
  git stash push -u -m "repo_manager auto stash"
  if errorlevel 1 exit /b 1
  exit /b 0
)
call :AUTO_COMMIT
exit /b %ERRORLEVEL%

:AUTO_COMMIT
setlocal DisableDelayedExpansion
set "MSG="
set /p "MSG=Commit message (empty=wip): "
if not defined MSG set "MSG=wip"
set "MSG=%MSG:"='%"
endlocal & set "MSG=%MSG%"

git add -A
if errorlevel 1 exit /b 1
git commit -m "%MSG%"
exit /b %ERRORLEVEL%


:: =========================
:: UPSTREAM MIRROR (no checkout main)
:: =========================
:MIRROR_UPSTREAM_TO_MAIN
if "%HAS_UPSTREAM%"=="0" exit /b 0

echo.
echo --- Mirror upstream/%UPSTREAM_HEAD% -> %MAIN_BRANCH% (no checkout) ---
git fetch upstream --prune >nul 2>nul
if errorlevel 1 exit /b 1

git show-ref --verify --quiet refs/remotes/upstream/%UPSTREAM_HEAD%
if errorlevel 1 exit /b 1

git branch -f %MAIN_BRANCH% upstream/%UPSTREAM_HEAD% >nul 2>nul
if errorlevel 1 exit /b 1

git push --force-with-lease origin %MAIN_BRANCH% >nul 2>nul
exit /b %ERRORLEVEL%


:: =========================
:: SIMPLE REPO BIDIRECTIONAL SYNC
:: =========================
:SYNC_SIMPLE_BIDIR_MAIN
echo.
echo --- Simple sync: %MAIN_BRANCH% <-> origin/%REMOTE_MAIN% ---
git fetch origin --prune >nul 2>nul
if errorlevel 1 exit /b 1

call :CHECKOUT_OR_CREATE %MAIN_BRANCH% origin/%REMOTE_MAIN%
if errorlevel 1 exit /b 1

call :DIRTY_PROMPT_SIMPLE
if errorlevel 1 exit /b 1

git fetch origin --prune >nul 2>nul
if errorlevel 1 exit /b 1

set "BEHIND=0"
set "AHEAD=0"
for /f "tokens=1,2" %%a in ('git rev-list --left-right --count origin/%REMOTE_MAIN%...%MAIN_BRANCH% 2^>nul') do (
  set "BEHIND=%%a"
  set "AHEAD=%%b"
)

echo INFO: ahead=%AHEAD% behind=%BEHIND%
if "%AHEAD%"=="0" if "%BEHIND%"=="0" exit /b 0

if not "%AHEAD%"=="0" if "%BEHIND%"=="0" (
  git push origin %MAIN_BRANCH%:%REMOTE_MAIN%
  exit /b %ERRORLEVEL%
)

if "%AHEAD%"=="0" if not "%BEHIND%"=="0" (
  git pull --rebase origin %REMOTE_MAIN%
  exit /b %ERRORLEVEL%
)

echo.
echo WARNING: diverged (both local and remote have new commits).
choice /c ARF /n /m "[A] Abort  [R] Rebase onto origin then push  [F] Force-with-lease push local: "
if errorlevel 3 (
  git push --force-with-lease origin %MAIN_BRANCH%:%REMOTE_MAIN%
  exit /b %ERRORLEVEL%
)
if errorlevel 2 (
  git pull --rebase origin %REMOTE_MAIN%
  if errorlevel 1 exit /b 1
  git push origin %MAIN_BRANCH%:%REMOTE_MAIN%
  exit /b %ERRORLEVEL%
)
exit /b 1


:: =========================
:: CORE OPS (must RETURN)
:: =========================
:SYNC
call :SETUP
if errorlevel 1 exit /b 1

call :CONDA_ACTIVATE
call :ENSURE_WORK
if errorlevel 1 (
  echo ERROR: cannot ensure work branch
  exit /b 1
)

if "%HAS_UPSTREAM%"=="0" (
  call :SYNC_SIMPLE_BIDIR_MAIN
  exit /b %ERRORLEVEL%
)

:: upstream repo: work branch only
call :CHECKOUT_OR_CREATE %WORK_EFF% origin/%WORK_EFF% >nul 2>nul

call :IS_DIRTY
if not errorlevel 1 (
  echo.
  echo WARNING: uncommitted changes on %WORK_EFF%.
  choice /c YN /n /m "Continue anyway (Y) Abort (N): "
  if errorlevel 2 (echo Aborted. & exit /b 1)
)

call :MIRROR_UPSTREAM_TO_MAIN
if errorlevel 1 (echo ERROR: mirror failed & exit /b 1)

echo.
echo --- Pull work (rebase): origin/%WORK_EFF% ---
git fetch origin --prune >nul 2>nul
git pull --rebase origin %WORK_EFF%
if errorlevel 1 (echo ERROR: pull work failed & exit /b 1)

call :CONDA_ENV_UPDATE
call :OPEN_CODE
exit /b 0


:MERGE
call :SETUP
if errorlevel 1 exit /b 1

if "%HAS_UPSTREAM%"=="0" (
  echo INFO: no upstream remote; MERGE skipped.
  exit /b 0
)

call :CONDA_ACTIVATE
call :ENSURE_WORK
if errorlevel 1 (echo ERROR: cannot ensure work & exit /b 1)

call :CHECKOUT_OR_CREATE %WORK_EFF% origin/%WORK_EFF% >nul 2>nul
git pull --rebase origin %WORK_EFF%
if errorlevel 1 (echo ERROR: pull work failed & exit /b 1)

call :MIRROR_UPSTREAM_TO_MAIN
if errorlevel 1 (echo ERROR: mirror failed & exit /b 1)

echo.
echo --- Create backup branch ---
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "TS=%%T"
set "BKP=backup/%WORK_EFF%-%TS%"

git branch "%BKP%"
if errorlevel 1 (echo ERROR: backup create failed & exit /b 1)

git push -u origin "%BKP%"
if errorlevel 1 (echo ERROR: backup push failed & exit /b 1)

echo.
echo --- Merge %MAIN_BRANCH% -> %WORK_EFF% ---
git merge %MAIN_BRANCH%
if errorlevel 1 (
  echo.
  echo MERGE CONFLICT.
  echo Resolve, then: git add . ^& git commit ^& git push origin %WORK_EFF%
  echo Or abort:      git merge --abort
  echo Backup: %BKP%
  exit /b 1
)

git push origin %WORK_EFF%
if errorlevel 1 (echo ERROR: push failed & exit /b 1)

echo OK: MERGE done. Backup: %BKP%
exit /b 0


:SAVE
call :SETUP
if errorlevel 1 exit /b 1

call :CONDA_ACTIVATE
call :ENSURE_WORK
if errorlevel 1 exit /b 1

call :CHECKOUT_OR_CREATE %WORK_EFF% origin/%WORK_EFF% >nul 2>nul

call :IS_DIRTY
if not errorlevel 1 (
  call :AUTO_COMMIT
  if errorlevel 1 (echo ERROR: commit failed & exit /b 1)
)

git push origin %WORK_EFF%
if errorlevel 1 (echo ERROR: push failed & exit /b 1)

echo OK: pushed %WORK_EFF% to origin.
exit /b 0


:: =========================
:: SESSION (controller)
:: =========================
:SESSION
call :SYNC
if errorlevel 1 exit /b 1

echo.
echo --- SESSION (same window) ---
echo Commands: help, status, sync, merge, save/exit
echo.

:SESSION_LOOP
set "LINE="
set /p "LINE=repo_manager> "
call :TRIM_LINE

if not defined LINE goto SESSION_LOOP

set "CMD="
for /f "tokens=1" %%A in ("!LINE!") do set "CMD=%%A"
if not defined CMD goto SESSION_LOOP

if /i "!CMD!"=="help"   (call :HELP & goto SESSION_LOOP)
if /i "!CMD!"=="status" (git status -sb & goto SESSION_LOOP)

if /i "!CMD!"=="sync"   (call :SYNC & goto SESSION_LOOP)
if /i "!CMD!"=="begin"  (call :SYNC & goto SESSION_LOOP)

if /i "!CMD!"=="merge"  (
  if "%HAS_UPSTREAM%"=="1" (call :MERGE) else (echo INFO: no upstream; merge ignored.)
  goto SESSION_LOOP
)

if /i "!CMD!"=="save"   (call :SAVE & exit /b %ERRORLEVEL%)
if /i "!CMD!"=="exit"   (call :SAVE & exit /b %ERRORLEVEL%)

echo Unknown command: "!LINE!"  ^(type "help"^)
goto SESSION_LOOP
