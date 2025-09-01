@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ===== settings =====
if "%~1"=="" (
  set "REPO=C:\Users\206429264\Projects\openssl"
) else (
  set "REPO=%~1"
)

rem ===== fetch tags =====
pushd "%REPO%" || (echo Repo not found: %REPO% & exit /b 1)
git fetch --tags --quiet

rem ===== discover 3.x minors with at least one STABLE tag (no -alpha/-beta/-rc) =====
set n=0
for /f "usebackq delims=" %%T in (`git tag -l "openssl-3.*" --sort=-version:refname`) do (
  for /f "tokens=2-5 delims=-." %%A in ("%%T") do (
    set "MAJ=%%A"
    set "MIN=%%B"
    set "REL=%%C"
    set "SUF=%%D"
  )
  if "!MAJ!"=="3" if not defined SUF (
    if not defined SEEN_!MIN! (
      set "SEEN_!MIN!=1"
      set /a n+=1
      set "MENU_!n!=!MIN!"
    )
  )
)

if %n%==0 echo No stable 3.x tags found. & popd & exit /b 1

echo(
for /l %%I in (1,1,%n%) do (
  call set "M=%%MENU_%%I%%"
  echo   %%I^) openssl-3.!M!
)

set /p sel=Select a branch (1-%n%) ^> 
if not defined MENU_%sel% (echo Invalid selection & popd & exit /b 1)

set "MINOR="
call set "MINOR=%%MENU_%sel%%%"
if not defined MINOR (echo Failed to resolve selection & popd & exit /b 1)

echo Branch: openssl-3.!MINOR!
echo(

rem ===== list STABLE release tags for that minor (descending) =====
set r=0
for /f "usebackq delims=" %%T in (`git tag -l "openssl-3.!MINOR!.*" --sort=-version:refname`) do (
  for /f "tokens=2-5 delims=-." %%A in ("%%T") do (
    set "REL=%%C"
    set "SUF=%%D"
  )
  if not defined SUF (
    set /a r+=1
    set "TAG_!r!=%%T"
    echo   !r!^) %%T
  )
)
if %r%==0 echo No stable releases found for openssl-3.!MINOR!. & popd & exit /b 1

set /p sel2=Select a release (1-%r%) ^> 

rem ===== resolve tag: number -> TAG_n; otherwise treat as exact tag =====
set "TAG="
set "NONNUM="
for /f "delims=0123456789" %%Z in ("%sel2%") do set "NONNUM=%%Z"
if not defined NONNUM (
  call set "TAG=%%TAG_%sel2%%%"
) else (
  set "TAG=%sel2%"
)

if not defined TAG (echo No tag selected. & popd & exit /b 1)

rem ===== validate tag exists =====
set "TAG_OK="
for /f "usebackq delims=" %%C in (`git tag -l "%TAG%"`) do set "TAG_OK=1"
if not defined TAG_OK (echo Tag "%TAG%" not found. & popd & exit /b 1)

echo Release: %TAG%

rem ===== parse version components =====
for /f "tokens=2-4 delims=-." %%a in ("%TAG%") do (
  set "MAJOR=%%a"
  set "MINOR=%%b"
  set "RELEASE=%%c"
)
set "VERSION=%MAJOR%.%MINOR%.%RELEASE%"
set "BRANCH=openssl-%MAJOR%.%MINOR%"

rem ===== export ONLY the requested variables =====
endlocal & (
  set "MAJOR=%MAJOR%"
  set "MINOR=%MINOR%"
  set "RELEASE=%RELEASE%"
  set "VERSION=%VERSION%"
  set "BRANCH=%BRANCH%"
  set "TAG=%TAG%"
)
popd
exit /b 0
