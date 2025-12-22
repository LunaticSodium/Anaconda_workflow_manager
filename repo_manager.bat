@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: =========================
:: CONFIG
:: =========================
:: If REPO_DIR is empty, use the directory of this .bat file.
set "REPO_DIR="
set "ENV_NAME=my_env"
set "MAIN_BRANCH=main"
set "WORK_BRANCH=work"

:: =========================
:: ENTRY
:: =========================
if /i "%~1"=="BEGIN"    goto BEGIN
if /i "%~1"=="MERGE"    goto MERGE
if /i "%~1"=="END"      goto ENDOP
if /i "%~1"=="ENDOP"    goto ENDOP
if /i "%~1"=="SESSION"  goto SESSION
goto MENU

:PRINT_HELP
echo.
echo ======================================================
echo  Repo Manager
echo ======================================================
echo  This tool assumes:
echo    - remotes: origin (your fork), upstream (author)
echo    - branches: %MAIN_BRANCH% (mirror), %WORK_BRANCH% (your work)
echo.
echo  Recommended workflow:
echo    1) BEGIN   : sync %WORK_BRANCH% from origin + mirror upstream -> %MAIN_BRANCH%
echo    2) MERGE   : bring %MAIN_BRANCH% updates into %WORK_BRANCH% (creates a backup branch)
echo    3) END     : commit (if needed) + push %WORK_BRANCH% to origin
echo.
echo  Session mode:
echo    SESSION : BEGIN, then opens a shell. Type 'exit' to run END automatically.
echo.
echo  Direct mode:
echo    repo_manager.bat BEGIN
echo    repo_manager.bat MERGE
echo    repo_manager.bat END
echo    repo_manager.bat SESSION
echo ======================================================
echo.
exit /b 0

:MENU
cls
call :PRINT_HELP
echo  [B] BEGIN    - Sync and open VS Code (optional shell)
echo  [M] MERGE    - Merge %MAIN_BRANCH% into %WORK_BRANCH%
echo  [E] END      - Commit/push %WORK_BRANCH% to origin
echo  [S] SESSION  - BEGIN then auto-END on normal exit
echo  [Q] Quit
echo.
choice /c BMESQ /n /m "Select Action: "
if errorlevel 5 exit /b 0
if errorlevel 4 goto SESSION
if errorlevel 3 goto ENDOP
if errorlevel 2 goto MERGE
if errorlevel 1 goto BEGIN
goto MENU

:SETUP
if not defined REPO_DIR set "REPO_DIR=%~dp0"
cd /d "%REPO_DIR%" || (echo ERROR: Cannot find directory: %REPO_DIR% & pause & exit /b 1)

where git >nul 2>nul || (echo ERROR: git not found in PATH & pause & exit /b 1)
git rev-parse --is-inside-work-tree >nul 2>nul || (echo ERROR: Not a git repo & pause & exit /b 1)

git remote get-url origin  >nul 2>nul || (echo ERROR: 'origin' remote not found & pause & exit /b 1)
git remote get-url upstream >nul 2>nul || (echo ERROR: 'upstream' remote not found & echo Run: git remote add upstream [URL] & pause & exit /b 1)

git fetch upstream --prune >nul 2>nul
git fetch origin --prune  >nul 2>nul

set "UPSTREAM_BRANCH="
for /f "delims=" %%R in ('git symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2^>nul') do set "UPSTREAM_BRANCH=%%R"
if defined UPSTREAM_BRANCH (
  set "UPSTREAM_BRANCH=!UPSTREAM_BRANCH:upstream/=!"
) else (
  set "UPSTREAM_BRANCH=%MAIN_BRANCH%"
)

call :ACTIVATE_CONDA
exit /b 0

:ACTIVATE_CONDA
if "%ENV_NAME%"=="" exit /b 0
if "%CONDA_DEFAULT_ENV%"=="%ENV_NAME%" exit /b 0

set "CONDA_BAT="
for %%A in (
  "%USERPROFILE%\anaconda3\condabin\conda.bat"
  "%USERPROFILE%\miniconda3\condabin\conda.bat"
  "C:\ProgramData\anaconda3\condabin\conda.bat"
  "C:\ProgramData\miniconda3\condabin\conda.bat"
) do if exist "%%~A" set "CONDA_BAT=%%~A"

if defined CONDA_BAT (
  call "%CONDA_BAT%" activate "%ENV_NAME%" >nul 2>nul
  if errorlevel 1 echo WARN: conda activate failed for %ENV_NAME%
  exit /b 0
)

where conda >nul 2>nul || exit /b 0
call conda activate "%ENV_NAME%" >nul 2>nul
if errorlevel 1 echo WARN: conda activate failed for %ENV_NAME%
exit /b 0

:ENSURE_CLEAN_OR_HANDLE
git status --porcelain | findstr . >nul
if errorlevel 1 exit /b 0

echo.
echo WARNING: Uncommitted changes detected:
git status --porcelain
echo.
choice /c YNS /n /m "Continue (Y) Abort (N) Stash (S): "
if errorlevel 3 (
  git stash push -u -m "repo_manager pre-op stash" || (echo ERROR: stash failed & exit /b 1)
  exit /b 0
)
if errorlevel 2 exit /b 1
exit /b 0

:CHECKOUT_OR_CREATE
:: %1 = branch, %2 = startpoint (optional)
git show-ref --verify --quiet refs/heads/%~1
if errorlevel 1 (
  if "%~2"=="" (exit /b 1)
  git checkout -B %~1 %~2 >nul 2>nul
  if errorlevel 1 exit /b 1
  exit /b 0
)
git checkout %~1 >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

:SYNC_MIRROR
echo.
echo --- Mirroring upstream/%UPSTREAM_BRANCH% -> %MAIN_BRANCH% ---
call :CHECKOUT_OR_CREATE %MAIN_BRANCH% upstream/%UPSTREAM_BRANCH% || (echo ERROR: cannot checkout/create %MAIN_BRANCH% & exit /b 1)

call :ENSURE_CLEAN_OR_HANDLE || exit /b 1

git fetch upstream --prune || exit /b 1
git reset --hard upstream/%UPSTREAM_BRANCH% || exit /b 1
git push --force-with-lease origin %MAIN_BRANCH% || exit /b 1
exit /b 0

:UPDATE_ENV
echo.
echo --- Checking env YAML ---
if exist environment.yml (
  conda env update -f environment.yml --prune
  exit /b 0
)
if exist env.yml (
  conda env update -f env.yml --prune
  exit /b 0
)
exit /b 0

:OPEN_VSCODE
where code >nul 2>nul
if %errorlevel%==0 start "" code .
exit /b 0

:BEGIN
call :SETUP || exit /b 1

call :SYNC_MIRROR || (echo ERROR: mirror failed & pause & exit /b 1)

echo.
echo --- Syncing %WORK_BRANCH% from origin ---
call :CHECKOUT_OR_CREATE %WORK_BRANCH% origin/%WORK_BRANCH% || (
  echo ERROR: cannot checkout/create %WORK_BRANCH% (does origin/%WORK_BRANCH% exist?)
  pause
  exit /b 1
)

call :ENSURE_CLEAN_OR_HANDLE || (echo Aborted. & pause & exit /b 1)
git pull --rebase origin %WORK_BRANCH% || (echo ERROR: pull failed & pause & exit /b 1)

call :UPDATE_ENV
call :OPEN_VSCODE

if /i "%~2"=="NOSHELL" exit /b 0
echo.
echo --- BEGIN complete. You can run commands here. Type 'exit' to close this shell. ---
cmd /k
exit /b 0

:MERGE
call :SETUP || exit /b 1

call :SYNC_MIRROR || (echo ERROR: mirror failed & pause & exit /b 1)

echo.
echo --- Preparing %WORK_BRANCH% ---
call :CHECKOUT_OR_CREATE %WORK_BRANCH% origin/%WORK_BRANCH% || (
  echo ERROR: cannot checkout/create %WORK_BRANCH% (does origin/%WORK_BRANCH% exist?)
  pause
  exit /b 1
)

call :ENSURE_CLEAN_OR_HANDLE || (echo Aborted. & pause & exit /b 1)
git pull --rebase origin %WORK_BRANCH% || (echo ERROR: pull failed & pause & exit /b 1)

echo.
echo --- Creating backup branch ---
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "TS=%%T"
set "BKP=backup/%WORK_BRANCH%-%TS%"

git branch "%BKP%" || (echo ERROR: backup create failed & pause & exit /b 1)
git push -u origin "%BKP%" || (echo ERROR: backup push failed & pause & exit /b 1)

echo.
echo --- Merging %MAIN_BRANCH% -> %WORK_BRANCH% ---
git merge %MAIN_BRANCH%
if errorlevel 1 (
  echo.
  echo MERGE CONFLICT.
  echo Resolve conflicts, then:
  echo   git add .
  echo   git commit
  echo   git push origin %WORK_BRANCH%
  echo Or abort:
  echo   git merge --abort
  echo Backup branch: %BKP%
  pause
  exit /b 1
)

git push origin %WORK_BRANCH% || (echo ERROR: push failed & pause & exit /b 1)

echo.
echo OK: MERGE complete. Backup: %BKP%
pause
goto MENU

:ENDOP
call :SETUP || exit /b 1

call :CHECKOUT_OR_CREATE %WORK_BRANCH% origin/%WORK_BRANCH% || (
  echo ERROR: cannot checkout/create %WORK_BRANCH% (does origin/%WORK_BRANCH% exist?)
  pause
  exit /b 1
)

git status --porcelain | findstr . >nul
if not errorlevel 1 (
  echo.
  git status
  set "MSG="
  set /p MSG=Commit message (empty = wip): 
  if "!MSG!"=="" set "MSG=wip"
  git add -A || (echo ERROR: git add failed & pause & exit /b 1)
  git commit -m "!MSG!" || (echo ERROR: git commit failed & pause & exit /b 1)
)

git push origin %WORK_BRANCH% || (echo ERROR: push failed & pause & exit /b 1)
echo.
echo OK: %WORK_BRANCH% pushed to origin.

if /i "%~2"=="NOMENU" exit /b 0
pause
goto MENU

:SESSION
call :SETUP || exit /b 1

call :BEGIN DUMMY NOSHELL || exit /b 1
echo.
echo --- SESSION ACTIVE ---
echo You're on %WORK_BRANCH%. Type 'exit' to run END and close.
cmd /k

call :ENDOP DUMMY NOMENU
exit /b 0
