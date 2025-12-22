@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ======================================================
rem Self-relaunch from TEMP so branch switching/reset won't
rem delete the running .bat (safe to keep this file in work branch)
rem ======================================================
if not defined REPO_MGR_RELAUNCHED (
  set "REPO_MGR_RELAUNCHED=1"
  set "REPO_MGR_HOME=%~dp0"
  set "REPO_MGR_ORIG=%~f0"
  set "REPO_MGR_TMP=%TEMP%\repo_manager_%RANDOM%%RANDOM%.bat"
  copy /y "%REPO_MGR_ORIG%" "%REPO_MGR_TMP%" >nul 2>nul
  if not exist "%REPO_MGR_TMP%" (
    echo ERROR: cannot create temp copy in %TEMP%
    pause
    exit /b 1
  )
  call "%REPO_MGR_TMP%" %*
  set "RC=%ERRORLEVEL%"
  del /q "%REPO_MGR_TMP%" >nul 2>nul
  exit /b %RC%
)

rem ======================================================
rem CONFIG
rem ======================================================
rem If REPO_DIR is empty, use the directory where the ORIGINAL .bat is located.
set "REPO_DIR="
set "ENV_NAME=BTO_ML"
set "MAIN_BRANCH=main"
set "WORK_BRANCH=work"

rem ======================================================
rem ENTRY
rem ======================================================
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
echo  Remotes  : origin (your fork), upstream (author)
echo  Branches : %MAIN_BRANCH% (mirror), %WORK_BRANCH% (your work)
echo.
echo  Use:
echo    BEGIN   - mirror upstream -> %MAIN_BRANCH%, sync %WORK_BRANCH%, update env, open VS Code
echo    MERGE   - create backup, merge %MAIN_BRANCH% into %WORK_BRANCH%, push
echo    END     - commit (if needed) + push %WORK_BRANCH%
echo    SESSION - BEGIN then open shell. Type 'exit' to auto-END.
echo.
echo  Tip: if you choose Stash during prompts, restore later with:
echo    git stash pop
echo ======================================================
echo.
exit /b 0

:MENU
cls
call :PRINT_HELP
echo  [B] BEGIN
echo  [M] MERGE
echo  [E] END
echo  [S] SESSION
echo  [Q] Quit
echo.
choice /c BMESQ /n /m "Select Action: "
if errorlevel 5 exit /b 0
if errorlevel 4 goto SESSION
if errorlevel 3 goto ENDOP
if errorlevel 2 goto MERGE
if errorlevel 1 goto BEGIN
goto MENU

rem ======================================================
rem SETUP
rem ======================================================
:SETUP
if not defined REPO_DIR (
  if defined REPO_MGR_HOME (set "REPO_DIR=%REPO_MGR_HOME%") else set "REPO_DIR=%~dp0"
)
cd /d "%REPO_DIR%" || (echo ERROR: Cannot find directory: %REPO_DIR% & pause & exit /b 1)

where git >nul 2>nul || (echo ERROR: git not found in PATH & pause & exit /b 1)
git rev-parse --is-inside-work-tree >nul 2>nul || (echo ERROR: Not a git repo & pause & exit /b 1)

git remote get-url origin  >nul 2>nul || (echo ERROR: 'origin' remote not found & pause & exit /b 1)
git remote get-url upstream >nul 2>nul || (echo ERROR: 'upstream' remote not found & echo Run: git remote add upstream [URL] & pause & exit /b 1)

git fetch upstream --prune >nul 2>nul
git fetch origin  --prune >nul 2>nul

rem Try to keep upstream/HEAD updated (optional)
git remote set-head upstream -a >nul 2>nul

set "UPSTREAM_BRANCH="
for /f "delims=" %%R in ('git symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2^>nul') do set "UPSTREAM_BRANCH=%%R"
if defined UPSTREAM_BRANCH (
  set "UPSTREAM_BRANCH=!UPSTREAM_BRANCH:upstream/=!"
) else (
  rem Fallback parsing (may contact remote on some setups)
  for /f "tokens=3" %%B in ('git remote show upstream ^| findstr /c:"HEAD branch:"') do set "UPSTREAM_BRANCH=%%B"
)

if not defined UPSTREAM_BRANCH set "UPSTREAM_BRANCH=%MAIN_BRANCH%"

call :FIND_CONDA
exit /b 0

rem ======================================================
rem CONDA
rem ======================================================
:FIND_CONDA
set "CONDA_BAT="
set "CONDA_BASE="

rem 1) best: conda info --base
where conda >nul 2>nul
if %errorlevel%==0 (
  for /f "usebackq delims=" %%B in (`conda info --base 2^>nul`) do set "CONDA_BASE=%%B"
  if defined CONDA_BASE if exist "%CONDA_BASE%\condabin\conda.bat" set "CONDA_BAT=%CONDA_BASE%\condabin\conda.bat"
)

rem 2) next: where conda (bat)
if not defined CONDA_BAT (
  for /f "delims=" %%P in ('where conda 2^>nul') do (
    if /i "%%~xP"==".bat" (
      set "CONDA_BAT=%%~fP"
      goto :FIND_CONDA_DONE
    )
  )
)

rem 3) common installs
if not defined CONDA_BAT (
  for %%A in (
    "%USERPROFILE%\anaconda3\condabin\conda.bat"
    "%USERPROFILE%\miniconda3\condabin\conda.bat"
    "C:\ProgramData\anaconda3\condabin\conda.bat"
    "C:\ProgramData\miniconda3\condabin\conda.bat"
  ) do if exist "%%~A" set "CONDA_BAT=%%~A"
)

:FIND_CONDA_DONE
exit /b 0

:CONDA_ACTIVATE
if "%ENV_NAME%"=="" exit /b 0
if not defined CONDA_BAT (
  echo WARN: conda not found (cannot activate %ENV_NAME%)
  exit /b 0
)
if "%CONDA_DEFAULT_ENV%"=="%ENV_NAME%" exit /b 0

call "%CONDA_BAT%" activate "%ENV_NAME%" >nul 2>nul
if errorlevel 1 (
  echo WARN: conda activate failed for %ENV_NAME%
  echo HINT: run: conda env list
  exit /b 0
)
exit /b 0

:CONDA_ENV_UPDATE
if "%ENV_NAME%"=="" exit /b 0
if not defined CONDA_BAT exit /b 0

if exist environment.yml (
  call "%CONDA_BAT%" env update -n "%ENV_NAME%" -f environment.yml --prune
  exit /b 0
)
if exist env.yml (
  call "%CONDA_BAT%" env update -n "%ENV_NAME%" -f env.yml --prune
  exit /b 0
)
exit /b 0

rem ======================================================
rem SAFETY
rem ======================================================
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
rem %1 = branch, %2 = startpoint
git show-ref --verify --quiet refs/heads/%~1
if errorlevel 1 (
  if "%~2"=="" exit /b 1
  git checkout -B %~1 %~2 >nul 2>nul
  if errorlevel 1 exit /b 1
  exit /b 0
)
git checkout %~1 >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

rem ======================================================
rem CORE OPS
rem ======================================================
:SYNC_MIRROR
echo.
echo --- Mirroring upstream/%UPSTREAM_BRANCH% -> %MAIN_BRANCH% ---
git fetch upstream --prune || exit /b 1

call :CHECKOUT_OR_CREATE %MAIN_BRANCH% upstream/%UPSTREAM_BRANCH% || (echo ERROR: cannot checkout/create %MAIN_BRANCH% & exit /b 1)
call :ENSURE_CLEAN_OR_HANDLE || exit /b 1

git reset --hard upstream/%UPSTREAM_BRANCH% || exit /b 1
git push --force-with-lease origin %MAIN_BRANCH% || exit /b 1
exit /b 0

:OPEN_VSCODE
where code >nul 2>nul
if %errorlevel%==0 start "" code .
exit /b 0

rem ======================================================
rem COMMANDS
rem ======================================================
:BEGIN
call :SETUP || exit /b 1

call :CONDA_ACTIVATE
call :SYNC_MIRROR || (echo ERROR: mirror failed & pause & exit /b 1)

echo.
echo --- Syncing %WORK_BRANCH% from origin ---
git fetch origin --prune || (echo ERROR: fetch origin failed & pause & exit /b 1)

call :CHECKOUT_OR_CREATE %WORK_BRANCH% origin/%WORK_BRANCH% || (
  echo ERROR: cannot checkout/create %WORK_BRANCH% (does origin/%WORK_BRANCH% exist?)
  pause
  exit /b 1
)

call :ENSURE_CLEAN_OR_HANDLE || (echo Aborted. & pause & exit /b 1)
git pull --rebase origin %WORK_BRANCH% || (echo ERROR: pull failed & pause & exit /b 1)

call :CONDA_ENV_UPDATE
call :OPEN_VSCODE

if /i "%~2"=="NOSHELL" exit /b 0
echo.
echo --- BEGIN complete. Type 'exit' to close this shell. ---
cmd /k
exit /b 0

:MERGE
call :SETUP || exit /b 1

call :CONDA_ACTIVATE
call :SYNC_MIRROR || (echo ERROR: mirror failed & pause & exit /b 1)

echo.
echo --- Preparing %WORK_BRANCH% ---
git fetch origin --prune >nul 2>nul
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

call :CONDA_ACTIVATE

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
