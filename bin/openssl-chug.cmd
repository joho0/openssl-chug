@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem =========================
rem OpenSSL Chug - main build
rem =========================

rem --- parse args ---
rem usage: openssl-chug.cmd [-h|--help] [-v|--verbose]
rem        openssl-chug.cmd [REPO] [INSTALL_ROOT] [-platform x64|x86] [--source|-s] [-v|--verbose]
set "CHUG_VERSION=1.0"
set "WITH_SOURCE=0"
set "VERBOSE=0"
set "SHOW_HELP="
set "PLATFORM="
set "ARG1="
set "ARG2="

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--help"     ( set "SHOW_HELP=1"   & shift & goto :parse_args )
if /i "%~1"=="-h"         ( set "SHOW_HELP=1"   & shift & goto :parse_args )
if /i "%~1"=="--verbose"  ( set "VERBOSE=1"     & shift & goto :parse_args )
if /i "%~1"=="-v"         ( set "VERBOSE=1"     & shift & goto :parse_args )
if /i "%~1"=="--source"   ( set "WITH_SOURCE=1" & shift & goto :parse_args )
if /i "%~1"=="-s"         ( set "WITH_SOURCE=1" & shift & goto :parse_args )
if /i "%~1"=="-platform"  ( set "PLATFORM=%~2"  & shift & shift & goto :parse_args )
if /i "%~1"=="--platform" ( set "PLATFORM=%~2"  & shift & shift & goto :parse_args )
if not defined ARG1 ( set "ARG1=%~1" & shift & goto :parse_args )
if not defined ARG2 ( set "ARG2=%~1" & shift & goto :parse_args )
shift
goto :parse_args
:args_done

if defined SHOW_HELP goto :USAGE

rem --- platform: default x64; accept x64 or x86 only ---
if not defined PLATFORM set "PLATFORM=x64"
if /i "%PLATFORM%"=="x64" ( set "PLATFORM=x64" ) else if /i "%PLATFORM%"=="x86" ( set "PLATFORM=x86" ) else ( echo [ERR] Unsupported -platform: "%PLATFORM%" ^(use x64 or x86^) & exit /b 1 )

rem --- settings / validation ---
if not defined ARG1 ( set "REPO=%USERPROFILE%\Projects\openssl" ) else ( set "REPO=%ARG1%" )
if not defined ARG2 ( set "INSTALL_ROOT=%USERPROFILE%\OpenSSL" ) else ( set "INSTALL_ROOT=%ARG2%" )

rem trim trailing backslashes
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"
if "%INSTALL_ROOT:~-1%"=="\" set "INSTALL_ROOT=%INSTALL_ROOT:~0,-1%"

rem --- REPO must exist and look like OpenSSL ---
if not exist "%REPO%\*" ( echo [ERR] REPO not found: "%REPO%" & exit /b 1 )
if not exist "%REPO%\README.md" ( echo [ERR] README.md missing under "%REPO%" & exit /b 1 )
rem Require README.md line 1 (allow leading '#' or spaces)
findstr /n /r "^" "%REPO%\README.md" | findstr /r "^1:[# ]*Welcome to the OpenSSL Project" >nul
if errorlevel 1 ( echo [ERR] README.md line 1 must be: "Welcome to the OpenSSL Project" & exit /b 1 )

rem --- INSTALL_ROOT: ensure valid directory (prompt to create) ---
if exist "%INSTALL_ROOT%\*" goto :inst_ok
if exist "%INSTALL_ROOT%" ( echo [ERR] INSTALL_ROOT exists but is not a directory: "%INSTALL_ROOT%" & exit /b 1 )
call :V [CHUG] WARN: INSTALL_ROOT not found: "%INSTALL_ROOT%"
echo INSTALL_ROOT not found: "%INSTALL_ROOT%"
choice /C YN /M "Create it now?"
if errorlevel 2 ( echo [ERR] Aborted; INSTALL_ROOT missing. & exit /b 1 )
mkdir "%INSTALL_ROOT%" 2>nul
if errorlevel 1 ( echo [ERR] Failed to create INSTALL_ROOT: "%INSTALL_ROOT%" & exit /b 1 )
call :V [CHUG] Created INSTALL_ROOT: "%INSTALL_ROOT%"

:inst_ok
rem --- banner ---
call :V [CHUG] REPO="%REPO%"
call :V [CHUG] INSTALL_ROOT="%INSTALL_ROOT%"
call :V [CHUG] Include source in output: %WITH_SOURCE%
echo(
echo OpenSSL Chug v%CHUG_VERSION%

rem --- tag picker (self-contained: branch -> tag) ---
call :PICK_TAG "%REPO%"
if errorlevel 1 goto ERR_TAG

rem --- build menu (minimal) ---
echo(
call :V [CHUG] Select a build (default 1):
echo 1^) secure
echo 2^) weak
echo 3^) fips
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
call :V [CHUG] Build: %BUILD_KIND%
call :V [CHUG] Platform: %PLATFORM%
echo(

rem --- derive paths (platform-scoped so x64/x86 don't collide) ---
set "OUTROOT=%INSTALL_ROOT%\%BRANCH%\%TAG%\%BUILD_KIND%\%PLATFORM%"
set "SRC_DIR=%OUTROOT%\src"
set "PREFIX=%OUTROOT%\install"
set "OPENSSLDIR=%PREFIX%\ssl"

rem --- git/perl checks ---
where git >nul 2>nul || goto ERR_GIT
where perl >nul 2>nul || goto ERR_PERL

rem --- ensure MSVC toolchain (nmake) for the target platform ---
rem x64 (default): keep an existing tools env if nmake is already on PATH.
rem x86: always load the matching cross env so we don't build with the wrong arch.
if /i "%PLATFORM%"=="x64" (
  where nmake >nul 2>nul || (
    call :BOOTSTRAP_MSVC
    where nmake >nul 2>nul || goto ERR_NMAKE
  )
) else (
  call :BOOTSTRAP_MSVC
  where nmake >nul 2>nul || goto ERR_NMAKE
)

rem --- asm check (optional) ---
set "ASM_OPT="
where nasm >nul 2>nul || (
  set "ASM_OPT=no-asm"
  echo [INFO] NASM not found; building with no-asm.
)

rem --- ensure folders exist ---
if not exist "%OUTROOT%\"    mkdir "%OUTROOT%"    >nul 2>nul
if not exist "%PREFIX%\"     mkdir "%PREFIX%"     >nul 2>nul
if not exist "%OPENSSLDIR%\" mkdir "%OPENSSLDIR%" >nul 2>nul

echo [INFO] CHUGALUG!
echo(

rem --- prepare git worktree at the tag ---
echo [INFO] Preparing %TAG% (%BUILD_KIND% %PLATFORM%)...
pushd "%REPO%" || goto ERR_REPO
if exist "%SRC_DIR%\*" call :REMOVE_WORKTREE "%SRC_DIR%"
git worktree add --force --detach "%SRC_DIR%" "%TAG%"
if errorlevel 1 (
  popd
  goto ERR_WORKTREE
)
popd

rem --- configure build ---
pushd "%SRC_DIR%" || goto ERR_SRCDIR
set "CFG_TARGET=VC-WIN64A"
if /i "%PLATFORM%"=="x86" set "CFG_TARGET=VC-WIN32"
set "CFG_BUILDOPT="
if /i "%BUILD_KIND%"=="secure" set "CFG_BUILDOPT=no-legacy"
if /i "%BUILD_KIND%"=="weak"   set "CFG_BUILDOPT=enable-legacy"
if /i "%BUILD_KIND%"=="fips"   set "CFG_BUILDOPT=enable-fips"

rem NOTE: Put options first, target last. Do NOT pass "release".
echo(
echo [INFO] Configuring %TAG% (%BUILD_KIND% %PLATFORM%)...
echo perl Configure shared %ASM_OPT% "--prefix=%PREFIX%" "--openssldir=%OPENSSLDIR%" %CFG_BUILDOPT% %CFG_TARGET%
perl Configure shared %ASM_OPT% "--prefix=%PREFIX%" "--openssldir=%OPENSSLDIR%" %CFG_BUILDOPT% %CFG_TARGET%
if errorlevel 1 goto ERR_CONFIG

rem --- build & install ---
echo(
echo [INFO] Building %TAG% (%BUILD_KIND% %PLATFORM%)...
nmake /nologo clean >nul 2>nul
nmake /nologo || goto ERR_BUILD

echo(
echo [INFO] Installing to: %PREFIX%
rem fips builds must also install the FIPS module and run fipsinstall
rem (install_fips installs fips.dll and generates %OPENSSLDIR%\fipsmodule.cnf)
set "INSTALL_TARGETS=install_sw install_ssldirs"
if /i "%BUILD_KIND%"=="fips" set "INSTALL_TARGETS=install_sw install_ssldirs install_fips"
nmake /nologo %INSTALL_TARGETS% || goto ERR_INSTALL

rem --- optional: write example provider configs per build ---
set "CNF_SEC=%OPENSSLDIR%\openssl-secure.cnf"
set "CNF_WEAK=%OPENSSLDIR%\openssl-weak.cnf"
set "CNF_FIPS=%OPENSSLDIR%\openssl-fips.cnf"
set "README=%OUTROOT%\README.txt"

if /i "%BUILD_KIND%"=="secure" call :WRITE_SECURE "%CNF_SEC%"
if /i "%BUILD_KIND%"=="weak"   call :WRITE_WEAK   "%CNF_WEAK%"
if /i "%BUILD_KIND%"=="fips"   call :WRITE_FIPS   "%CNF_FIPS%" "%OPENSSLDIR%\fipsmodule.cnf"

rem --- write quickstart README ---
>"%README%" (
  echo OpenSSL Chug
  echo =============
  echo Tag: %TAG%
  echo Branch: %BRANCH%
  echo Version: %VERSION%
  echo Build: %BUILD_KIND%
  echo Platform: %PLATFORM%
  echo Install: %PREFIX%
  echo Include source in output: %WITH_SOURCE%
  echo(
  echo Usage:
  echo set "PATH=%PREFIX%\bin;%%PATH%%"
  echo ^(optional^) set OPENSSL_CONF to one of:
)
if exist "%CNF_SEC%"  >>"%README%" echo %CNF_SEC%
if exist "%CNF_WEAK%" >>"%README%" echo %CNF_WEAK%
if exist "%CNF_FIPS%" >>"%README%" echo %CNF_FIPS%
>>"%README%" (
  echo(
  echo Verify:
  echo openssl version -a
)

rem --- show result ---
echo(
echo [OK] Build complete.
echo [INFO] "%PREFIX%\bin\openssl.exe" version -a
"%PREFIX%\bin\openssl.exe" version -a
popd

rem --- cleanup src worktree unless keeping source ---
if "%WITH_SOURCE%"=="0" (
  echo [INFO] Cleaning up src worktree: "%SRC_DIR%"
  pushd "%REPO%" >nul 2>nul && (
    call :REMOVE_WORKTREE "%SRC_DIR%"
    popd
  )
) else (
  echo [INFO] Keeping src worktree: "%SRC_DIR%"
)

exit /b 0

:USAGE
echo OpenSSL Chug v%CHUG_VERSION% - Windows OpenSSL build helper
echo(
echo Usage:
echo   openssl-chug.cmd [-h^|--help] [-v^|--verbose]
echo   openssl-chug.cmd [REPO] [INSTALL_ROOT] [-platform x64^|x86] [--source ^| -s] [-v^|--verbose]
echo(
echo Arguments:
echo   REPO          Path to local OpenSSL git repo. Default: %%USERPROFILE%%\Projects\openssl
echo   INSTALL_ROOT  Root for installs/output.      Default: %%USERPROFILE%%\OpenSSL
echo(
echo Options:
echo   -platform ARCH Target architecture: x64 ^(default^) or x86 ^(cross-built from x64^).
echo   -s, --source   Keep the git worktree source in the output under ^"src^".
echo   -v, --verbose  Show detailed [CHUG] logs.
echo   -h, --help     Show this help and exit.
echo(
echo Examples:
echo   openssl-chug.cmd
echo   openssl-chug.cmd -platform x86
echo   openssl-chug.cmd -s
echo   openssl-chug.cmd -v
echo   openssl-chug.cmd C:\src\openssl D:\OpenSSL -platform x86 --source -v
exit /b 0

:: ------------------------------------------------------------
:: Tag picker (branch -> tag) - stable only (no alpha/beta/rc)
:: ------------------------------------------------------------
:PICK_TAG
rem args: %1 = REPO path
setlocal EnableExtensions EnableDelayedExpansion
set "_REPO=%~1"
pushd "%_REPO%" || ( endlocal & exit /b 1 )

rem Best-effort: refresh tags quietly so stale clones still work
git fetch --tags --prune --quiet >nul 2>nul

rem First pass: collect newest stable openssl-3.* tags; dedupe branches (major.minor)
set /a _bi=0
for /f "usebackq delims=" %%T in (`git tag -l "openssl-3.*" --sort=-v:refname`) do (
  set "t=%%T"
  set "skip="
  if not "!t:-alpha=!"=="!t!" set "skip=1"
  if not "!t:-beta=!"=="!t!"  set "skip=1"
  if not "!t:-rc=!"=="!t!"    set "skip=1"
  if not defined skip (
    set "v=!t:openssl-=!"
    for /f "tokens=1-2 delims=." %%a in ("!v!") do (
      set "maj=%%a"
      set "min=%%b"
    )
    set "br=openssl-!maj!.!min!"
    set "key=!br:.=_!"
    if not defined _SEEN_!key! (
      set /a _bi+=1
      set "_BR_!_bi!=!br!"
      set "_SEEN_!key!=1"
    )
  )
)

rem Remote fallback if nothing found locally
if !_bi! LSS 1 (
  for /f "usebackq tokens=3 delims=/" %%R in (`
    git ls-remote --tags origin "refs/tags/openssl-3.*" 2^>nul
  `) do (
    set "t=%%R"
    rem strip annotated-tag deref suffix (openssl-3.5.2^{})
    set "t=!t:^{}=!"
    set "skip="
    if not "!t:-alpha=!"=="!t!" set "skip=1"
    if not "!t:-beta=!"=="!t!"  set "skip=1"
    if not "!t:-rc=!"=="!t!"    set "skip=1"
    if not defined skip (
      set "v=!t:openssl-=!"
      for /f "tokens=1-2 delims=." %%a in ("!v!") do (
        set "maj=%%a"
        set "min=%%b"
      )
      set "br=openssl-!maj!.!min!"
      set "key=!br:.=_!"
      if not defined _SEEN_!key! (
        set /a _bi+=1
        set "_BR_!_bi!=!br!"
        set "_SEEN_!key!=1"
      )
    )
  )
)

if !_bi! LSS 1 ( popd & endlocal & exit /b 1 )

set "_BR_COUNT=%_bi%"
echo(
call :V [CHUG] Select a branch (default 1):
for /l %%N in (1,1,%_BR_COUNT%) do if defined _BR_%%N echo %%N^) !_BR_%%N!
set /p _bsel=Select a branch (1-%_BR_COUNT%) ^>
if not defined _bsel set "_bsel=1"
set "_nonn="
for /f "delims=0123456789" %%Z in ("%_bsel%") do set "_nonn=%%Z"
if defined _nonn set "_bsel=1"
if %_bsel% LSS 1 set "_bsel=1"
if %_bsel% GTR %_BR_COUNT% set "_bsel=1"
set "_BRANCH=!_BR_%_bsel%!"
call :V [CHUG] Branch: %_BRANCH%

rem Second pass: list tags under selected branch, newest first (stable only)
set /a _ti2=0
for /f "usebackq delims=" %%T in (`git tag -l "%_BRANCH%.*" --sort=-v:refname`) do (
  set "t=%%T"
  set "skip="
  if not "!t:-alpha=!"=="!t!" set "skip=1"
  if not "!t:-beta=!"=="!t!"  set "skip=1"
  if not "!t:-rc=!"=="!t!"    set "skip=1"
  if not defined skip (
    set /a _ti2+=1
    if !_ti2! LEQ 20 set "_T_!_ti2!=!t!"
  )
)
if !_ti2! LSS 1 ( popd & endlocal & exit /b 1 )

set "_TAG_COUNT=%_ti2%"
echo(
call :V [CHUG] Select a tag (default 1):
for /l %%N in (1,1,%_TAG_COUNT%) do if defined _T_%%N echo %%N^) !_T_%%N!
set /p _tsel=Select a tag (1-%_TAG_COUNT%) ^>
if not defined _tsel set "_tsel=1"
set "_nonn="
for /f "delims=0123456789" %%Z in ("%_tsel%") do set "_nonn=%%Z"
if defined _nonn set "_tsel=1"
if %_tsel% LSS 1 set "_tsel=1"
if %_tsel% GTR %_TAG_COUNT% set "_tsel=1"

set "_TAG=!_T_%_tsel%!"
set "_VERSION=%_TAG:openssl-=%"
call :V [CHUG] Tag: %_TAG%

popd
endlocal & (
  set "TAG=%_TAG%"
  set "VERSION=%_VERSION%"
  set "BRANCH=%_BRANCH%"
)
exit /b 0

:BOOTSTRAP_MSVC
rem vcvarsall.bat auto-detects the host and takes the target arch as an argument.
set "_VCARCH=amd64"
if /i "%PLATFORM%"=="x86" set "_VCARCH=x86"
for %%V in (
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvarsall.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
) do (
  if exist %%~fV (
    echo [INFO] Loading MSVC env: %%~fV %_VCARCH%
    call "%%~fV" %_VCARCH% >nul 2>nul
    goto :eof
  )
)
echo [WARN] Could not auto-locate Visual Studio vcvarsall.bat.
echo Either install VS Build Tools 2022 (C++ workloads) or run from a Native Tools prompt.
goto :eof

:REMOVE_WORKTREE
git worktree remove --force "%~1" >nul 2>nul
rmdir /s /q "%~1" >nul 2>nul
exit /b

:WRITE_SECURE
>"%~1" (
  echo openssl_conf = openssl_init
  echo(
  echo [openssl_init]
  echo providers = provider_sect
  echo(
  echo [provider_sect]
  echo default = default_sect
  echo(
  echo [default_sect]
  echo activate = 1
)
exit /b

:WRITE_WEAK
>"%~1" (
  echo openssl_conf = openssl_init
  echo(
  echo [openssl_init]
  echo providers = provider_sect
  echo(
  echo [provider_sect]
  echo default = default_sect
  echo legacy = legacy_sect
  echo(
  echo [default_sect]
  echo activate = 1
  echo(
  echo [legacy_sect]
  echo activate = 1
)
exit /b

:WRITE_FIPS
rem args: %1 = output .cnf path, %2 = path to generated fipsmodule.cnf
rem [fips_sect] is defined by the .include'd fipsmodule.cnf (self-test MAC values).
rem The base provider supplies non-crypto bits (encoders/PEM) the FIPS provider lacks.
>"%~1" (
  echo config_diagnostics = 1
  echo openssl_conf = openssl_init
  echo(
  echo .include %~2
  echo(
  echo [openssl_init]
  echo providers = provider_sect
  echo alg_section = algorithm_sect
  echo(
  echo [provider_sect]
  echo fips = fips_sect
  echo base = base_sect
  echo(
  echo [base_sect]
  echo activate = 1
  echo(
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

rem --- verbose echo helper (prints only when -v/--verbose is set) ---
:V
if "%VERBOSE%"=="1" echo %*
exit /b 0
