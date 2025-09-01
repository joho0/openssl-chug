@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem =========================
rem OpenSSL Chug - main build
rem =========================

rem --- settings / validation ---
rem usage: openssl-chug.cmd [REPO] [INSTALL_ROOT]

rem defaults (no blocks)
if "%~1"=="" set "REPO=%USERPROFILE%\Projects\openssl"
if not "%~1"=="" set "REPO=%~1"
if "%~2"=="" set "INSTALL_ROOT=%USERPROFILE%\OpenSSL"
if not "%~2"=="" set "INSTALL_ROOT=%~2"

rem trim trailing backslashes
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"
if "%INSTALL_ROOT:~-1%"=="\" set "INSTALL_ROOT=%INSTALL_ROOT:~0,-1%"

rem --- REPO must exist and look like OpenSSL ---
if not exist "%REPO%\*" call :die [CHUG] ERROR: REPO not found: "%REPO%"
if not exist "%REPO%\README.md" call :die [CHUG] ERROR: README.md missing under "%REPO%"

rem Require README.md line 1 (allow leading '#' or spaces)
findstr /n /r "^" "%REPO%\README.md" | findstr /r "^1:[# ]*Welcome to the OpenSSL Project" >nul
if errorlevel 1 call :die [CHUG] ERROR: README.md line 1 must be: "Welcome to the OpenSSL Project"

rem --- INSTALL_ROOT: ensure valid directory (prompt to create) ---
if exist "%INSTALL_ROOT%\*" goto :inst_ok
if exist "%INSTALL_ROOT%" call :die [CHUG] ERROR: INSTALL_ROOT exists but is not a directory: "%INSTALL_ROOT%"

echo [CHUG] WARN: INSTALL_ROOT not found: "%INSTALL_ROOT%"
choice /C YN /M "[CHUG] Create it now?"
if errorlevel 2 call :die [CHUG] ERROR: Aborted; INSTALL_ROOT missing.
mkdir "%INSTALL_ROOT%" 2>nul
if errorlevel 1 call :die [CHUG] ERROR: Failed to create INSTALL_ROOT: "%INSTALL_ROOT%"
echo [CHUG] Created INSTALL_ROOT: "%INSTALL_ROOT%"
:inst_ok

echo [CHUG] REPO="%REPO%"
echo [CHUG] INSTALL_ROOT="%INSTALL_ROOT%"

rem --- banner ---
echo CHUGALUG!
echo OpenSSL Chug v1.0

rem --- pick tag (exports: MAJOR MINOR RELEASE VERSION BRANCH TAG) ---
set "SCRIPT_DIR=%~dp0"
call "%SCRIPT_DIR%get-openssl-tag.cmd" "%REPO%"
if errorlevel 1 goto ERR_TAG

rem --- build menu (minimal) ---
echo(
echo   1^) secure
echo   2^) weak
echo   3^) fips
set /p BSEL=Select a build (1-3) ^> 
if not defined BSEL set "BSEL=1"
set "NONNUM="
for /f "delims=0123456789" %%Z in ("%BSEL%") do set "NONNUM=%%Z"
if defined NONNUM set "BSEL=1"

set "BUILD_KIND="
if "%BSEL%"=="1" set "BUILD_KIND=secure"
if "%BSEL%"=="2" set "BUILD_KIND=weak"
if "%BSEL%"=="3" set "BUILD_KIND=fips"
if not defined BUILD_KIND set "BUILD_KIND=secure"

echo Build: %BUILD_KIND%
echo(

rem --- derive paths ---
set "OUTROOT=%INSTALL_ROOT%\%BRANCH%\%TAG%\%BUILD_KIND%"
set "SRC_DIR=%OUTROOT%\src"
set "PREFIX=%OUTROOT%\install"
set "OPENSSLDIR=%PREFIX%\ssl"

rem --- git/perl checks ---
where git  >nul 2>nul
if errorlevel 1 goto ERR_GIT
where perl >nul 2>nul
if errorlevel 1 goto ERR_PERL

rem --- ensure MSVC toolchain (nmake); auto-bootstrap if needed ---
where nmake >nul 2>nul
if errorlevel 1 (
  call :BOOTSTRAP_MSVC
  where nmake >nul 2>nul
  if errorlevel 1 goto ERR_NMAKE
)

rem --- asm check (optional) ---
set "ASM_OPT="
where nasm>nul 2>nul
if errorlevel 1 (
  set "ASM_OPT=no-asm"
  echo [INFO] NASM not found; building with no-asm.
)

rem --- ensure folders exist ---
if not exist "%OUTROOT%\"     mkdir "%OUTROOT%"     >nul 2>nul
if not exist "%PREFIX%\"      mkdir "%PREFIX%"      >nul 2>nul
if not exist "%OPENSSLDIR%\"  mkdir "%OPENSSLDIR%"  >nul 2>nul

rem --- prepare git worktree at the tag ---
echo [INFO] Preparing %TAG% (%BUILD_KIND%)...
pushd "%REPO%"
if errorlevel 1 goto ERR_REPO
if exist "%SRC_DIR%\*" call :REMOVE_WORKTREE "%SRC_DIR%"
git worktree add --force --detach "%SRC_DIR%" "%TAG%"
if errorlevel 1 (
  popd
  goto ERR_WORKTREE
)
popd

rem --- configure build ---
pushd "%SRC_DIR%"
if errorlevel 1 goto ERR_SRCDIR

set "CFG_TARGET=VC-WIN64A"
set "CFG_BUILDOPT="
if /i "%BUILD_KIND%"=="secure" set "CFG_BUILDOPT=no-legacy"
if /i "%BUILD_KIND%"=="weak"   set "CFG_BUILDOPT=enable-legacy"
if /i "%BUILD_KIND%"=="fips"   set "CFG_BUILDOPT=enable-fips"

rem NOTE: Put options first, target last. Do NOT pass "release".
echo.
echo [INFO] Configuring %TAG% (%BUILD_KIND%)...
echo perl Configure shared %ASM_OPT% "--prefix=%PREFIX%" "--openssldir=%OPENSSLDIR%" %CFG_BUILDOPT% %CFG_TARGET%
perl Configure shared %ASM_OPT% "--prefix=%PREFIX%" "--openssldir=%OPENSSLDIR%" %CFG_BUILDOPT% %CFG_TARGET%
if errorlevel 1 goto ERR_CONFIG

rem --- build & install ---
echo(
echo [INFO] Building %TAG% (%BUILD_KIND%)...
nmake /nologo clean >nul 2>nul
nmake /nologo
if errorlevel 1 goto ERR_BUILD

echo(
echo [INFO] Installing to: %PREFIX%
nmake /nologo install_sw install_ssldirs
if errorlevel 1 goto ERR_INSTALL

rem --- optional: write example provider configs per build ---
set "CNF_SEC=%OPENSSLDIR%\openssl-secure.cnf"
set "CNF_WEAK=%OPENSSLDIR%\openssl-weak.cnf"
set "CNF_FIPS=%OPENSSLDIR%\openssl-fips.cnf"
set "README=%OUTROOT%\README.txt"

if /i "%BUILD_KIND%"=="secure" call :WRITE_SECURE "%CNF_SEC%"
if /i "%BUILD_KIND%"=="weak"   call :WRITE_WEAK   "%CNF_WEAK%"
if /i "%BUILD_KIND%"=="fips"   call :WRITE_FIPS   "%CNF_FIPS%"

rem --- write quickstart README ---
>"%README%" (
  echo OpenSSL Chug
  echo =============
  echo Tag:      %TAG%
  echo Branch:   %BRANCH%
  echo Version:  %VERSION%
  echo Build:    %BUILD_KIND%
  echo Install:  %PREFIX%
  echo.
  echo Usage:
  echo   set "PATH=%PREFIX%\bin;%%PATH%%"
  echo   ^(optional^) set "OPENSSL_CONF=" to one of:
)
if exist "%CNF_SEC%"  >>"%README%" echo     %CNF_SEC%
if exist "%CNF_WEAK%" >>"%README%" echo     %CNF_WEAK%
if exist "%CNF_FIPS%" >>"%README%" echo     %CNF_FIPS%

>>"%README%" (
  echo.
  echo Verify:
  echo   openssl version -a
)

rem --- show result ---
echo(
echo [OK] Build complete.
echo [INFO] "%PREFIX%\bin\openssl.exe" version -a
"%PREFIX%\bin\openssl.exe" version -a

popd
exit /b 0

:BOOTSTRAP_MSVC
for %%V in (
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
) do (
  if exist %%~fV (
    echo [INFO] Loading MSVC env: %%~fV
    call "%%~fV" >nul 2>nul
    goto :eof
  )
)
echo [WARN] Could not auto-locate Visual Studio vcvars64.bat.
echo        Either install VS Build Tools 2022 (C++ workloads) or run from the "x64 Native Tools" prompt.
goto :eof

:REMOVE_WORKTREE
git worktree remove --force "%~1" >nul 2>nul
rmdir /s /q "%~1" >nul 2>nul
exit /b

:WRITE_SECURE
>"%~1" (
  echo openssl_conf = openssl_init
  echo.
  echo [openssl_init]
  echo providers = provider_sect
  echo.
  echo [provider_sect]
  echo default = default_sect
  echo.
  echo [default_sect]
  echo activate = 1
)
exit /b

:WRITE_WEAK
>"%~1" (
  echo openssl_conf = openssl_init
  echo.
  echo [openssl_init]
  echo providers = provider_sect
  echo.
  echo [provider_sect]
  echo default = default_sect
  echo legacy  = legacy_sect
  echo.
  echo [default_sect]
  echo activate = 1
  echo.
  echo [legacy_sect]
  echo activate = 1
)
exit /b

:WRITE_FIPS
>"%~1" (
  echo openssl_conf = openssl_init
  echo.
  echo [openssl_init]
  echo providers = provider_sect
  echo alg_section = algorithm_sect
  echo.
  echo [provider_sect]
  echo fips    = fips_sect
  echo default = default_sect
  echo.
  echo [default_sect]
  echo activate = 1
  echo.
  echo [fips_sect]
  echo activate = 1
  echo.
  echo [algorithm_sect]
  echo default_properties = fips^=yes
)
exit /b

rem ===== errors =====
:ERR_TAG
echo [ERR] Tag selection failed.
exit /b 1

:ERR_GIT
echo [ERR] git not found in PATH.
exit /b 1

:ERR_PERL
echo [ERR] perl not found (install Strawberry Perl).
exit /b 1

:ERR_NMAKE
echo [ERR] nmake not found. Install VS Build Tools 2022 (C++ build tools + Windows SDK) or run from "x64 Native Tools".
exit /b 1

:ERR_REPO
echo [ERR] Repo not found: %REPO%
exit /b 1

:ERR_WORKTREE
echo [ERR] Failed to create worktree for %TAG%.
exit /b 1

:ERR_SRCDIR
echo [ERR] Missing worktree: %SRC_DIR%
exit /b 1

:ERR_CONFIG
echo [ERR] Configure failed.
popd
exit /b 1

:ERR_BUILD
echo [ERR] Build failed.
popd
exit /b 1

:ERR_INSTALL
echo [ERR] Install failed.
popd
exit /b 1

:die
echo %*
exit /b 1
