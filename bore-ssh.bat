@echo off
rem ============================================================
rem  bore-ssh.bat - SSH tunnel qua bore (Windows)
rem
rem  File duy nhat can chay tren Windows:
rem    [1] Setup SSH server + mo tunnel  (lan dau)
rem    [2] Mo tunnel                     (SSH da cai san)
rem    [3] SSH vao tunnel                (tu may khac)
rem    [4] Cai dat / cap nhat bore
rem
rem  Phan cai dat OpenSSH nam trong scripts\setup-sshd-windows.ps1
rem ============================================================
setlocal EnableDelayedExpansion
cd /d "%~dp0"

set "ROOT=%~dp0"
set "BIN=%ROOT%bin\bore.exe"
set "CONF=%ROOT%tunnel.conf"
set "EXAMPLE=%ROOT%tunnel.conf.example"
set "LOG=%ROOT%.bore-ssh.log"
set "STATE=%ROOT%.bore-ssh-last"
set "SETUPPS1=%ROOT%scripts\setup-sshd-windows.ps1"
set "BORE_VERSION=0.6.0"

set "ORIGARGS=%*"
set "MODE="
set "DRYRUN="
set "OPT_PORT="
set "OPT_PW="
set "OPT_USER="
set "OPT_SSHONLY="
set "OPT_SKIPPW="
set "OPT_HOURS="
set "BORE_STARTED="
set "BORE_PID="

:parse
if "%~1"=="" goto :parsed
if /i "%~1"=="-h" goto :help
if /i "%~1"=="help" (
  set "MODE=help"
  goto :help
)
if /i "%~1"=="--help" goto :help
if /i "%~1"=="setup" (
  set "MODE=setup"
  shift
  goto :parse
)
if /i "%~1"=="server" (
  set "MODE=server"
  shift
  goto :parse
)
if /i "%~1"=="client" (
  set "MODE=client"
  shift
  goto :parse
)
if /i "%~1"=="install" (
  set "MODE=install"
  shift
  goto :parse
)
if /i "%~1"=="st" (
  set "MODE=setup"
  shift
  goto :parse
)
if /i "%~1"=="s" (
  set "MODE=server"
  shift
  goto :parse
)
if /i "%~1"=="c" (
  set "MODE=client"
  shift
  goto :parse
)
if /i "%~1"=="i" (
  set "MODE=install"
  shift
  goto :parse
)
if /i "%~1"=="logs" (
  set "MODE=logs"
  shift
  goto :parse
)
if /i "%~1"=="l" (
  set "MODE=logs"
  shift
  goto :parse
)
if /i "%~1"=="--hours" (
  set "OPT_HOURS=%~2"
  shift
  shift
  goto :parse
)
if /i "%~1"=="--dry-run" (
  set "DRYRUN=1"
  shift
  goto :parse
)
if /i "%~1"=="--ssh-only" (
  set "OPT_SSHONLY=1"
  shift
  goto :parse
)
if /i "%~1"=="--skip-password" (
  set "OPT_SKIPPW=1"
  shift
  goto :parse
)
if /i "%~1"=="--port" (
  set "OPT_PORT=%~2"
  shift
  shift
  goto :parse
)
if /i "%~1"=="--password" (
  set "OPT_PW=%~2"
  shift
  shift
  goto :parse
)
if /i "%~1"=="--user" (
  set "OPT_USER=%~2"
  shift
  shift
  goto :parse
)
echo   [X] Tuy chon khong hop le: %~1
goto :help

:parsed
call :load_conf

if /i "%MODE%"=="setup"   goto :setup
if /i "%MODE%"=="server"  goto :server
if /i "%MODE%"=="client"  goto :client
if /i "%MODE%"=="install" goto :install
if /i "%MODE%"=="logs"    goto :logs
if /i "%MODE%"=="help"    goto :help
goto :menu


rem ============================================================
rem  MENU
rem ============================================================
:menu
cls
echo.
echo   ============================================================
echo      SSH over bore  -  tunnel helper
echo   ============================================================
echo      Relay server : %BORE_SERVER%
echo      SSH port     : %SSH_PORT%
echo      Bore binary  : %BORE_BIN%
echo   ------------------------------------------------------------
echo      [1] Setup SSH server + mo tunnel   (lan dau)
echo      [2] Mo tunnel                      (SSH da cai san)
echo      [3] SSH vao tunnel                 (tu may khac)
echo      [4] Cai dat / cap nhat bore
echo      [5] Xem log / kiem tra tan cong
echo      [6] Thoat
echo.
choice /c 123456 /n /m "  Chon 1-6: "
if errorlevel 6 goto :end
if errorlevel 5 goto :logs
if errorlevel 4 goto :install
if errorlevel 3 goto :client
if errorlevel 2 goto :server
if errorlevel 1 goto :setup


rem ============================================================
rem  SETUP: cai OpenSSH Server + mo tunnel
rem ============================================================
:setup
call :require_admin
if errorlevel 1 goto :setup_noadmin

rem --dry-run: chi in buoc, khong doi he thong
if defined DRYRUN goto :setup_conf

rem Da co quyen Admin: loai tru Defender TRUOC khi tai bore.
rem Neu khong, Defender se xoa bore.exe ngay khi file vua duoc giai nen.
call :exclude_defender

if not exist "%BIN%" call :do_install
if not exist "%BIN%" goto :setup_fail

:setup_conf
if not exist "%CONF%" if exist "%EXAMPLE%" copy /y "%EXAMPLE%" "%CONF%" >nul 2>&1
call :load_conf

set "FPORT=%OPT_PORT%"
if not defined FPORT set "FPORT=%SSH_PORT%"
if not defined FPORT set "FPORT=2222"
set "FUSER=%OPT_USER%"
if not defined FUSER set "FUSER=%USERNAME%"

if defined OPT_PW goto :setup_pw_done
if defined OPT_SKIPPW goto :setup_pw_done
if defined DRYRUN goto :setup_pw_done

echo.
echo   Mat khau Windows cua "%FUSER%" se dung de dang nhap SSH.
set "YN="
set /p "YN=  Dat mat khau MOI (tu sinh)? [y/N]: "
if /i "%YN%"=="y" goto :setup_pw_done
set "OPT_SKIPPW=1"
echo   [i] Giu nguyen mat khau hien tai cua "%FUSER%".

:setup_pw_done
echo.
echo   [*] Setup SSH server: cong %FPORT%, user %FUSER%
echo.

set "PSARGS=-Port %FPORT% -User "%FUSER%" -ConfPath "%CONF%""
if defined OPT_PW     set "PSARGS=!PSARGS! -Password "%OPT_PW%""
if defined OPT_SKIPPW set "PSARGS=!PSARGS! -NoPassword"
if defined DRYRUN     set "PSARGS=!PSARGS! -DryRun"

rem Xoa log cu de khong in nham log cua lan truoc khi PS1 fail som
if exist "%ROOT%logs\sshd-setup.log" del /q "%ROOT%logs\sshd-setup.log" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SETUPPS1%" !PSARGS!
set "PSRC=%ERRORLEVEL%"
if not "%PSRC%"=="0" goto :setup_ps_fail

rem Defender co the vua duoc loai tru -> tai lai bore neu file bi cach ly
if not exist "%BIN%" call :do_install
if not exist "%BIN%" goto :setup_fail

if defined OPT_SSHONLY goto :setup_only
if defined DRYRUN goto :end

echo.
echo   [..] Mo bore tunnel...
call :server
goto :end

:setup_only
echo.
echo   [i] Chi setup SSH, khong mo tunnel.
echo   [i] Mo tunnel sau bang:  bore-ssh.bat s
echo.
pause
goto :end

:setup_noadmin
echo.
if defined ADMIN_OK goto :setup_noadmin_ok
if defined ADMIN_FAIL goto :setup_ps_fail_bad
echo   [i] Chua setup duoc SSH server (khong co quyen Administrator).
echo   [i] Neu SSH da cai san, mo tunnel bang:  bore-ssh.bat s
echo.
pause
goto :end

:setup_noadmin_ok
echo   [i] Setup da hoan tat trong cua so Administrator.
echo   [i] Muon mo lai tunnel:  bore-ssh.bat s
echo.
pause
goto :end

:setup_ps_fail_bad
echo   [X] Cua so Administrator da dong nhung setup KHONG thanh cong.
call :show_setup_log
echo.
pause
goto :end

:setup_ps_fail
echo.
if "%PSRC%"=="2" echo   [X] Thieu quyen Administrator de cai SSH server.
echo   [X] Cai SSH server that bai (ma loi %PSRC%).
call :show_setup_log
echo.
pause
goto :end

:setup_fail
echo.
echo   [X] Setup that bai.
call :show_setup_log
echo.
pause
goto :end

rem Ghi SSH_USER=<user Windows hien tai> vao tunnel.conf (neu dang trong)
:save_conf_user
set "SSH_USER=%USERNAME%"
if not exist "%CONF%" exit /b 0
powershell -NoProfile -Command "$p='%CONF%'; $u='%USERNAME%'; $c=@(Get-Content -LiteralPath $p); $f=$false; $c = $c | ForEach-Object { if ($_ -match '^\s*SSH_USER\s*=') { 'SSH_USER=' + $u; $f=$true } else { $_ } }; if (-not $f) { $c += ('SSH_USER=' + $u) }; Set-Content -LiteralPath $p -Value $c -Encoding ASCII" >nul 2>&1
exit /b 0

rem In 20 dong cuoi cua log setup de biet loi that su
:show_setup_log
set "SLOG=%ROOT%logs\sshd-setup.log"
if not exist "%SLOG%" (
    echo   [i] Khong co log moi - loi xay ra truoc khi PS1 kip chay.
    exit /b 0
)
echo.
echo   --- 20 dong cuoi: %SLOG% ---
powershell -NoProfile -Command "Get-Content -LiteralPath '%SLOG%' -Tail 20 | ForEach-Object { '   ' + $_ }"
echo   --- het log ---
exit /b 0


rem ============================================================
rem  SERVER: expose local SSH port ra bore
rem ============================================================
:server
call :ensure_bore
if errorlevel 1 goto :server_back
call :verify_bore
if errorlevel 1 goto :server_back

rem Chua co SSH_USER trong tunnel.conf -> ghi user Windows hien tai vao
if not defined SSH_USER call :save_conf_user

set "PORTARG="
if not "%REMOTE_PORT%"=="" set "PORTARG=--port %REMOTE_PORT%"
set "BORECMD=%BORE_BIN% local %SSH_PORT% --to %BORE_SERVER% %PORTARG% %BORE_ARGS%"
set "BORECMD=%BORECMD:  = %"

if defined DRYRUN goto :server_dry

echo.
echo   [*] Mo tunnel: %BORECMD%
rem Log rieng cho moi lan chay: tranh bi khoa boi tien trinh bore cu
rem (neu dung chung .bore-ssh.log, port doc duoc co the la port CU)
set "RUNLOG=%TEMP%\bore-run-%RANDOM%%RANDOM%.log"
del /q "%RUNLOG%" >nul 2>&1
for %%F in ("%BORE_BIN%") do set "BORE_IMAGE=%%~nxF"
call :list_pids
set "PIDS_BEFORE=!PIDS!"
start "" /b cmd /c ""%BORE_BIN%" local %SSH_PORT% --to %BORE_SERVER% %PORTARG% %BORE_ARGS% > "%RUNLOG%" 2>&1"
set "BORE_STARTED=1"
call :capture_pid

call :wait_port
if not defined BORE_PORT goto :server_fail

rem Luu ban sao log de xem lai sau
copy /y "%RUNLOG%" "%LOG%" >nul 2>&1

call :show_endpoint

echo.
echo   [i] Tunnel dang chay. Nhan phim bat ky de DUNG tunnel va thoat.
pause >nul
call :stop_bore
echo   [i] Da dong tunnel.
if defined MODE goto :end
goto :menu

:server_dry
echo.
echo   [dry-run] Lenh se chay:
echo     %BORECMD%
echo.
if defined MODE goto :end
pause
goto :menu

:server_fail
call :stop_bore
echo.
echo   [X] Khong mo duoc tunnel.
if exist "%RUNLOG%" type "%RUNLOG%"
echo.
echo   Goi y:
echo     - Kiem tra ket noi internet / relay server.
echo     - Neu dat REMOTE_PORT, port do co the da bi nguoi khac dung.
if defined MODE goto :end
echo.
pause
goto :menu

:server_back
if defined MODE goto :end
echo.
pause
goto :menu


rem ============================================================
rem  CLIENT: SSH vao tunnel
rem ============================================================
:client
set "LAST_HOST="
set "LAST_PORT="
set "LAST_USER="
if exist "%STATE%" call :load_file "%STATE%"

set "DEF_HOST=%LAST_HOST%"
if not defined DEF_HOST set "DEF_HOST=%SERVER_HOST%"
set "DEF_PORT=%LAST_PORT%"
set "DEF_USER=%SSH_USER%"
if not defined DEF_USER set "DEF_USER=%LAST_USER%"

rem Neu da biet du host/port/user thi vao thang, khong hoi lai
set "CHOST=%LAST_HOST%"
set "CPORT=%LAST_PORT%"
set "CUSER=%DEF_USER%"
if defined CHOST if defined CPORT if defined CUSER goto :client_run

echo.
echo   --- SSH vao tunnel ---
echo   Tunnel phai duoc mo truoc do bang che do Server tren may kia.
echo   User = tai khoan Windows tren may ao. Kiem tra bang: whoami
echo.

set "IN="
set /p "IN=  Host [%DEF_HOST%]: "
if defined IN set "CHOST=%IN%"
if not defined CHOST set "CHOST=%DEF_HOST%"

set "IN="
if defined DEF_PORT set /p "IN=  Port [%DEF_PORT%]: "
if not defined DEF_PORT set /p "IN=  Port: "
if defined IN set "CPORT=%IN%"
if not defined CPORT set "CPORT=%DEF_PORT%"
if not defined CPORT goto :client_noport

set "IN="
set /p "IN=  User [%DEF_USER%]: "
if defined IN set "CUSER=%IN%"
if not defined CUSER set "CUSER=%DEF_USER%"

:client_run
set "SSHCMD=ssh -p %CPORT% -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30"
if not "%SSH_KEY%"=="" set SSHCMD=!SSHCMD! -i "!SSH_KEY!"
if not "%CUSER%"=="" set SSHCMD=!SSHCMD! !CUSER!@!CHOST!
if "%CUSER%"=="" set SSHCMD=!SSHCMD! !CHOST!

>"%STATE%" echo LAST_HOST=%CHOST%
>>"%STATE%" echo LAST_PORT=%CPORT%
>>"%STATE%" echo LAST_USER=%CUSER%

echo.
echo   [*] %SSHCMD%
echo.
if defined DRYRUN goto :client_dry

!SSHCMD!
echo.
echo   [i] Phien SSH ket thuc.
pause
if defined MODE goto :end
goto :menu

:client_dry
echo   [dry-run] Khong ket noi. Bo --dry-run de chay that.
echo.
if defined MODE goto :end
pause
goto :menu

:client_noport
echo.
echo   [X] Chua co port. Chay che do Server truoc, hoac nhap port thu cong.
echo.
if defined MODE goto :end
pause
goto :menu


rem ============================================================
rem  INSTALL
rem ============================================================
:install
call :do_install
if errorlevel 1 goto :install_done
echo.
if defined MODE goto :end
pause
goto :menu

:install_done
echo.
if defined MODE goto :end
pause
goto :menu

:do_install
where curl >nul 2>&1
if errorlevel 1 goto :install_nocurl

set "URL=https://github.com/ekzhang/bore/releases/download/v%BORE_VERSION%/bore-v%BORE_VERSION%-x86_64-pc-windows-msvc.zip"
set "ZIP=%TEMP%\bore-%BORE_VERSION%.zip"
set "TMPD=%TEMP%\bore-unzip-%RANDOM%%RANDOM%"

echo.
echo   [*] Tai bore v%BORE_VERSION% cho Windows x64 ...
curl -L --fail --silent --show-error -o "%ZIP%" "%URL%"
if errorlevel 1 goto :install_fail

if not exist "%ROOT%bin" mkdir "%ROOT%bin" >nul 2>&1
mkdir "%TMPD%" >nul 2>&1
tar -xf "%ZIP%" -C "%TMPD%" 2>nul
if errorlevel 1 goto :install_ps

move /y "%TMPD%\bore.exe" "%BIN%" >nul 2>&1
rmdir /s /q "%TMPD%" >nul 2>&1
del /q "%ZIP%" >nul 2>&1
if not exist "%BIN%" goto :install_fail
call :verify_bore
if errorlevel 1 exit /b 1
echo   [+] Da cai: %BIN%
echo.
echo   Luu y: Windows Defender doi khi bao nham bore.exe la virus.
echo          Neu file bi xoa, them thu muc bin vao danh sach loai tru.
exit /b 0

:install_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%TMPD%' -Force" >nul 2>&1
if errorlevel 1 goto :install_fail
move /y "%TMPD%\bore.exe" "%BIN%" >nul 2>&1
rmdir /s /q "%TMPD%" >nul 2>&1
del /q "%ZIP%" >nul 2>&1
if not exist "%BIN%" goto :install_fail
call :verify_bore
if errorlevel 1 exit /b 1
echo   [+] Da cai: %BIN%
exit /b 0

:verify_bore
"%BIN%" --version >nul 2>&1
if not errorlevel 1 exit /b 0
if defined DEFENDER_FIXED goto :verify_bore_dead
echo.
echo   [X] bore.exe co tren dia nhung KHONG CHAY duoc.
echo       Windows Defender dang xoa/chan file (bao nham: Trojan:Win32/Kepavll).
echo       Cach sua: loai tru thu muc bin, roi tai lai bore.
echo.
choice /c YN /n /m "  Loai tru Defender cho %ROOT%bin va tai lai bore? [Y/n]: "
if errorlevel 2 goto :verify_bore_dead
set "DEFENDER_FIXED=1"
call :exclude_defender
if errorlevel 1 goto :verify_bore_dead
del /q "%BIN%" >nul 2>&1
call :do_install
exit /b %ERRORLEVEL%

:verify_bore_dead
echo.
echo   [X] Khong chay duoc bore.exe.
echo       Chay tay trong PowerShell (Run as Administrator):
echo         Add-MpPreference -ExclusionPath "%ROOT%bin"
echo       Roi:
echo         bore-ssh.bat install
echo.
exit /b 1

rem Them loai tru Defender cho %ROOT%bin (tu xin quyen Admin neu can)
:exclude_defender
if not exist "%ROOT%scripts\defender-exclude.ps1" goto :exclude_defender_manual
set "ISADMIN="
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }" >nul 2>&1
if not errorlevel 1 set "ISADMIN=1"
if defined ISADMIN goto :exclude_defender_direct

echo   [..] Can quyen Administrator de loai tru Defender, dang mo UAC...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Start-Process -FilePath 'powershell' -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%ROOT%scripts\defender-exclude.ps1','-Path','%ROOT%bin'; exit $p.ExitCode } catch { Write-Host ''; Write-Host ('  [X] ' + $_.Exception.Message); exit 2 }"
exit /b %ERRORLEVEL%

:exclude_defender_direct
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\defender-exclude.ps1" -Path "%ROOT%bin"
exit /b %ERRORLEVEL%

:exclude_defender_manual
echo   [i] Khong thay scripts\defender-exclude.ps1 - bo qua loai tru Defender.
exit /b 1

:install_fail
echo.
echo   [X] Cai dat that bai.
echo       Tai thu cong: %URL%
echo       Giai nen bore.exe vao: %ROOT%bin\
echo       Neu file tai ve bi xoa ngay: Windows Defender dang cach ly.
echo       Chay "bore-ssh.bat setup" (Admin) de tu them loai tru.
exit /b 1

:install_nocurl
echo.
echo   [X] Khong tim thay curl.exe. Windows 10 tro len da co san.
echo       Tai thu cong: https://github.com/ekzhang/bore/releases
echo       Giai nen bore.exe vao: %ROOT%bin\
exit /b 1


rem ============================================================
rem  LOGS: kiem tra tan cong / brute-force
rem ============================================================
:logs
set "LHOURS=%OPT_HOURS%"
if not defined LHOURS set "LHOURS=24"
set "LPORT=%SSH_PORT%"
if not defined LPORT set "LPORT=2222"
echo.
echo   [*] Phan tich log SSH trong %LHOURS% gio qua...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\check-log.ps1" -Hours %LHOURS% -Port %LPORT%
echo.
echo   [i] Log day du: Event Viewer ^> Applications and Services Logs
echo       ^> OpenSSH ^> Operational
echo.
if defined MODE goto :end
pause
goto :menu


rem ============================================================
rem  HELP
rem ============================================================
:help
echo.
echo   bore-ssh - SSH tunnel qua bore
echo.
echo   Cach dung:
echo     bore-ssh.bat                    Mo menu
echo     bore-ssh.bat setup              Cai SSH server + mo tunnel  (can Admin)
echo     bore-ssh.bat server             Chi mo tunnel
echo     bore-ssh.bat client             SSH vao tunnel da expose
echo     bore-ssh.bat install            Tai bore v%BORE_VERSION% vao bin\
echo     bore-ssh.bat logs               Xem log + kiem tra tan cong
echo     bore-ssh.bat help               Tro giup
echo.
echo   Tuy chon cho "setup":
echo     --port N           cong SSH noi bo (mac dinh 2222)
echo     --password P       mat khau cho user (mac dinh: tu sinh)
echo     --user NAME        user dung de SSH (mac dinh: user dang chay)
echo     --ssh-only         chi setup SSH, khong mo tunnel
echo     --skip-password    khong doi mat khau
echo     --dry-run          chi in buoc, khong thay doi he thong
echo.
echo   Cau hinh: tunnel.conf  xem tunnel.conf.example
echo.
if defined MODE goto :end
pause
goto :menu


rem ============================================================
rem  SUBROUTINES
rem ============================================================

rem Yeu cau quyen Administrator, tu mo lai cua so UAC neu can
:require_admin
net session >nul 2>&1
if not errorlevel 1 exit /b 0

echo.
echo   [..] Can quyen Administrator, dang mo cua so UAC...
set "REARGS=setup"
if defined OPT_PORT   set REARGS=!REARGS! --port !OPT_PORT!
if defined OPT_USER   set REARGS=!REARGS! --user "!OPT_USER!"
if defined OPT_PW     set REARGS=!REARGS! --password "!OPT_PW!"
if defined OPT_SSHONLY set "REARGS=!REARGS! --ssh-only"
if defined OPT_SKIPPW set "REARGS=!REARGS! --skip-password"
if defined DRYRUN     set "REARGS=!REARGS! --dry-run"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $p = Start-Process -FilePath '%~f0' -ArgumentList '%REARGS%' -Verb RunAs -Wait -PassThru; exit $p.ExitCode } catch { Write-Host ''; Write-Host ('  [X] Khong mo duoc cua so Administrator: ' + $_.Exception.Message); exit 2 }"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" set "ADMIN_OK=1"
if not "%RC%"=="0" set "ADMIN_FAIL=1"
if not "%RC%"=="0" echo   [X] Cua so Administrator dong voi ma loi %RC%.
exit /b 1

rem Doc file KEY=VALUE (bo qua dong trong va dong bat dau bang #)
:load_file
if not exist "%~1" exit /b 1
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~1") do set "%%A=%%B"
exit /b 0

:load_conf
if exist "%CONF%" call :load_file "%CONF%"
if not defined BORE_SERVER set "BORE_SERVER=bore.pub"
if not defined SSH_PORT set "SSH_PORT=22"
if not defined BORE_BIN set "BORE_BIN=%BIN%"
set "SERVER_HOST=%BORE_SERVER%"
for /f "tokens=1 delims=:" %%A in ("%BORE_SERVER%") do set "SERVER_HOST=%%A"
exit /b 0

rem Bao dam co bore.exe (config -> bin\bore.exe -> PATH)
:ensure_bore
if exist "%BORE_BIN%" exit /b 0
if not "%BORE_BIN%"=="%BIN%" if exist "%BIN%" set "BORE_BIN=%BIN%" & exit /b 0
where bore >nul 2>&1
if errorlevel 1 goto :ensure_bore_missing
for /f "delims=" %%P in ('where bore 2^>nul') do set "BORE_BIN=%%P"
if exist "%BORE_BIN%" exit /b 0

:ensure_bore_missing
echo.
echo   [X] Khong tim thay bore tai: %BORE_BIN%
echo       Chay: bore-ssh.bat install
echo.
if defined MODE exit /b 1
pause
exit /b 1

rem Ghi lai PID cua tien trinh bore vua khoi dong
:capture_pid
set "BORE_PID="
for %%F in ("%BORE_BIN%") do set "BORE_IMAGE=%%~nxF"
call :list_pids
set "PIDS_AFTER=!PIDS!"
for %%P in (!PIDS_AFTER!) do (
  echo !PIDS_BEFORE! | findstr /c:" %%P " >nul
  if errorlevel 1 set "BORE_PID=%%P"
)
exit /b 0

:list_pids
set "PIDS= "
if not defined BORE_IMAGE exit /b 0
for /f "tokens=2 delims=," %%P in ('tasklist /fi "imagename eq %BORE_IMAGE%" /fo csv /nh 2^>nul') do set "PIDS=!PIDS!%%~P "
exit /b 0

rem Cho toi khi bore in ra "listening at host:port"
:wait_port
set "BORE_PORT="
set /a _TRIES=0
:wait_loop
call :parse_log
if defined BORE_PORT exit /b 0
if exist "%RUNLOG%" findstr /i /c:"error" /c:"failed" "%RUNLOG%" >nul 2>&1
if not errorlevel 1 exit /b 1
set /a _TRIES+=1
if %_TRIES% geq 25 exit /b 1
ping -n 2 127.0.0.1 >nul 2>&1
goto :wait_loop

rem Lay port cuoi cung tu dong "listening at <server>:<port>"
:parse_log
set "_LINE="
for /f "usebackq delims=" %%L in (`findstr /c:"listening at " "%RUNLOG%" 2^>nul`) do set "_LINE=%%L"
if not defined _LINE exit /b 1
set "_TAIL=!_LINE:*listening at =!"
if not defined _TAIL exit /b 1
for %%W in (!_TAIL!) do set "_TAIL=%%W"
:parse_split
for /f "tokens=1,* delims=:" %%A in ("!_TAIL!") do (
  if "%%B"=="" set "BORE_PORT=%%A" & exit /b 0
  set "_TAIL=%%B"
)
goto :parse_split

:show_endpoint
rem Tat delayed expansion o day: mat khau co the chua "!" (bi cmd an mat)
setlocal DisableDelayedExpansion
set "SSHUSER=%SSH_USER%"
rem Chua cau hinh user -> dung tai khoan Windows dang chay (chinh la user de SSH vao)
if not defined SSHUSER set "SSHUSER=%USERNAME%"
if not defined SSHUSER set "SSHUSER=YOUR_USER"

rem Doc user + mat khau da luu tu lan setup (.ssh-password)
set "PWSAVED="
if exist "%ROOT%.ssh-password" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ROOT%.ssh-password") do (
    if /i "%%A"=="SSH_USER"     set "SSHUSER=%%B"
    if /i "%%A"=="SSH_PASSWORD" set "PWSAVED=%%B"
)

rem User co dau cach -> phai de trong ngoac kep
set "QUSER=%SSHUSER%"
if not "%SSHUSER%"=="%SSHUSER: =%" set "QUSER="%SSHUSER%""

rem Luu lai de che do client dung lai (khong phai hoi)
>"%STATE%" echo LAST_HOST=%SERVER_HOST%
>>"%STATE%" echo LAST_PORT=%BORE_PORT%
>>"%STATE%" echo LAST_USER=%SSHUSER%

echo.
echo   ============================================================
echo      TUNNEL DANG MO
echo   ============================================================
echo      Cong khai : %SERVER_HOST%:%BORE_PORT%
echo.
echo      ^>^>^> DAN NGUYEN DONG NAY VAO MAY KHAC:
echo.
echo          ssh -p %BORE_PORT% %QUSER%@%SERVER_HOST%
echo.
if defined PWSAVED echo      Mat khau  : %PWSAVED%
if defined PWSAVED echo.
echo      User      : %SSHUSER%  (tai khoan Windows tren may nay)
echo   ------------------------------------------------------------
echo      Thu ngay tai may nay truoc:
echo          ssh -p %SSH_PORT% %QUSER%@localhost
echo   ------------------------------------------------------------
echo      Hoac dan vao %%USERPROFILE%%\.ssh\config de go ngan:
echo         Host vm
echo             HostName %SERVER_HOST%
echo             Port %BORE_PORT%
echo             User %QUSER%
echo      Roi chi can go:  ssh vm
echo   ============================================================
if defined PWSAVED echo      Ghi chu: mat khau luu trong .ssh-password (da gitignore)
endlocal
exit /b 0

:stop_bore
if not defined BORE_STARTED exit /b 0
if not defined BORE_PID goto :stop_bore_img
taskkill /f /pid %BORE_PID% >nul 2>&1
goto :stop_bore_done
:stop_bore_img
taskkill /f /im %BORE_IMAGE% >nul 2>&1
:stop_bore_done
if defined RUNLOG if exist "%RUNLOG%" del /q "%RUNLOG%" >nul 2>&1
set "BORE_STARTED="
set "BORE_PID="
exit /b 0

:end
call :stop_bore
endlocal
exit /b 0
