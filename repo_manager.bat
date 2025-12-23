@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =========================
:: CONFIG
:: =========================
:: Put this file in the repo root. Leave REPO_DIR empty to use the .bat directory.
set "REPO_DIR="
set "ENV_NAME="

set "MAIN_BRANCH=main"
set "WORK_BRANCH=work"
set "AUTO_OPEN_CODE=1"

:: Default: no args -> SESSION
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
echo    status   - git status -sb
echo    begin    - run BEGIN again
echo    merge    - run MERGE (only if upstream exists)
echo    save     - run END (commit/push) and exit
echo    exit     - same as save
echo    menu     - go to menu
echo    help     - show this help
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
:: CONDA (silent, no command-substitution)
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
:: HELPERS
:: =========================
:OPEN_CODE
if "%AUTO_OPEN_CODE%"=="1" (
  where code >nul 2>nul
  if %errorlevel%==0 start "" code .
)
exit /b 0

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
:: MIRROR (no checkout main)
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

if /i "%~2"=="NOMENU" exit /b 0
pause
goto MENU

:SESSION
call :BEGIN || exit /b 1
echo.
echo --- SESSION (same window) ---
echo Type "help" for commands. Type "save" or "exit" to commit/push and close.
echo.

:SESSION_LOOP
set "CMD="
set /p "CMD=repo_manager> "
if /i "%CMD%"=="help"   (call :HELP & goto SESSION_LOOP)
if /i "%CMD%"=="status" (git status -sb & goto SESSION_LOOP)
if /i "%CMD%"=="begin"  (call :BEGIN & goto SESSION_LOOP)
if /i "%CMD%"=="merge"  (call :MERGE & goto SESSION_LOOP)
if /i "%CMD%"=="menu"   goto MENU
if /i "%CMD%"=="save"   (call :ENDOP DUMMY NOMENU & exit /b 0)
if /i "%CMD%"=="exit"   (call :ENDOP DUMMY NOMENU & exit /b 0)
echo Unknown command. Type "help".
goto SESSION_LOOP
