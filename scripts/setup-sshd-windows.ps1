<#
    setup-sshd-windows.ps1
    Tu dong cai + cau hinh OpenSSH Server tren Windows Server.

    Duoc goi tu bore-ssh.bat (khong can chay truc tiep).

    Cac buoc:
      1. Cai OpenSSH Server (Windows Capability, fallback Win32-OpenSSH)
      2. Bat service sshd (automatic + start)
      3. Mo firewall cho cong SSH
      4. Sua sshd_config: Port, PasswordAuthentication yes
      5. Dat mat khau cho user (neu co)
      6. Tu kiem tra lai toan bo
      7. Ghi SSH_PORT / SSH_USER vao tunnel.conf

    Exit code: 0 = thanh cong, 1 = co loi, 2 = thieu quyen.
#>
[CmdletBinding()]
param(
    [int]$Port = 2222,
    [string]$User = $env:USERNAME,
    [string]$Password = "",
    [string]$ConfPath = "",
    [Alias('SkipPassword')][switch]$NoPassword,
    [switch]$SkipFirewall,
    [switch]$WindowsUpdate,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:Failed = $false

# -------------------------------------------------------------
# Log file: bore-ssh.bat in 20 dong cuoi khi setup that bai
# -------------------------------------------------------------
$script:LogFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'logs\sshd-setup.log'

function Write-Log([string]$m) {
    try {
        $dir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m
        [IO.File]::AppendAllText($script:LogFile, $line + "`r`n", (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

try {
    if (Test-Path -LiteralPath $script:LogFile) {
        Remove-Item -LiteralPath $script:LogFile -Force -ErrorAction SilentlyContinue
    }
} catch { }

# Bat moi loi khong luong truoc -> ghi log + in ro rang (khong chet im lang)
trap {
    $msg = $_.Exception.Message
    Write-Host ''
    Write-Host "[fail] $msg" -ForegroundColor Red
    Write-Log "LOI: $msg"
    try {
        if ($_.InvocationInfo) {
            Write-Log ('  tai dong ' + $_.InvocationInfo.ScriptLineNumber + ': ' + $_.InvocationInfo.Line.Trim())
        }
        Write-Log ('  stack: ' + $_.ScriptStackTrace)
    } catch { }
    exit 1
}

function Step($m) { Write-Host "[..]   $m" -ForegroundColor Cyan; Write-Log "[..] $m" }
function Ok($m)   { Write-Host "[ok]   $m" -ForegroundColor Green; Write-Log "[ok] $m" }
function Warn($m) { Write-Host "[warn] $m" -ForegroundColor Yellow; Write-Log "[warn] $m" }
function Fail($m) { Write-Host "[fail] $m" -ForegroundColor Red; $script:Failed = $true; Write-Log "[fail] $m" }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SshdPath {
    $candidates = @(
        (Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'),
        (Join-Path $env:ProgramFiles 'OpenSSH\sshd.exe')
    )
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { return $p } }
    $cmd = Get-Command sshd.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Test-PortOpen([int]$p) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $p, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(700)) { $c.Close(); return $false }
        $c.EndConnect($iar)
        $c.Close()
        return $true
    } catch { return $false }
}

function Set-ConfValue([string]$path, [string]$key, [string]$value) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return }
    $lines = @(Get-Content -LiteralPath $path)
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($key))\s*=") {
            $lines[$i] = "$key=$value"
            $found = $true
        }
    }
    if (-not $found) { $lines += "$key=$value" }
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding($false)))
}

# -------------------------------------------------------------
Write-Host ''
Write-Host '============================================================' -ForegroundColor White
Write-Host '  CAI DAT SSH SERVER (Windows)' -ForegroundColor White
Write-Host '============================================================' -ForegroundColor White
Write-Log '=== Cai dat SSH server (Windows) ==='

if (-not (Test-Admin)) {
    Fail 'Can quyen Administrator. Chay: bore-ssh.bat setup'
    exit 2
}

if ($DryRun) {
    Warn 'DRY-RUN: khong thay doi he thong.'
    Step "se cai OpenSSH Server, cong $Port, user $User"
    exit 0
}

# -------------------------------------------------------------
# 0. Loai tru Windows Defender cho thu muc bin
#    (bore.exe hay bi bao nham la virus va bi cach ly)
# -------------------------------------------------------------
try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $binDir = Join-Path $repoRoot 'bin'
    if (-not (Test-Path -LiteralPath $binDir)) {
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    }
    if ((Get-Command Add-MpPreference -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $binDir)) {
        $excl = @((Get-MpPreference).ExclusionPath)
        if ($excl -notcontains $binDir) {
            Add-MpPreference -ExclusionPath $binDir
            Ok "Defender: da loai tru $binDir"
        } else {
            Ok "Defender: $binDir da duoc loai tru"
        }
    }
} catch {
    Warn "Khong them duoc loai tru Defender: $($_.Exception.Message)"
}

# -------------------------------------------------------------
# 1. Cai OpenSSH Server
# -------------------------------------------------------------
$sshd = Get-SshdPath
if ($sshd) {
    Ok "OpenSSH Server da co: $sshd"
} else {
    Step 'Chua co OpenSSH Server, dang cai...'
    $installed = $false

    # Mac dinh KHONG dung Windows Update (cham 5-15 phut): tai truc tiep tu GitHub.
    # Dung -WindowsUpdate neu muon ban in-box cua Microsoft.
    if ($WindowsUpdate -and (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue)) {
        try {
            # Ten chinh thuc theo tai lieu Microsoft; van do lai neu may dung ten khac
            $capName = 'OpenSSH.Server~~~~0.0.1.0'
            $cap = Get-WindowsCapability -Online -Name $capName -ErrorAction SilentlyContinue
            if (-not $cap) {
                $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue |
                       Select-Object -First 1
                if ($cap) { $capName = $cap.Name }
            }
            if ($cap -and $cap.State -ne 'Installed') {
                Step "Add-WindowsCapability -Online -Name $capName"
                Warn 'Lay tu Windows Update - co the mat 5-15 phut. DUNG TAT cua so nay.'
                Add-WindowsCapability -Online -Name $capName | Out-Null
            }
            $sshd = Get-SshdPath
            if ($sshd) { $installed = $true; Ok 'Da cai qua Windows Capability' }
        } catch {
            Warn "Windows Capability loi: $($_.Exception.Message)"
        }
    }

    if (-not $installed) {
        Step 'Thu cai bang goi Win32-OpenSSH tu GitHub...'
        $zip = Join-Path $env:TEMP 'OpenSSH-Win64.zip'
        $urls = New-Object 'System.Collections.Generic.List[string]'

        # 1) Thu GitHub API (co timeout, khong treo vo han)
        try {
            $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest' `
                    -Headers @{ 'User-Agent' = 'bore-ssh-setup' } -UseBasicParsing -TimeoutSec 15
            $asset = $rel.assets | Where-Object { $_.name -match '^OpenSSH-Win64.*\.zip$' } |
                     Select-Object -First 1
            if ($asset) { $urls.Add($asset.browser_download_url) }
        } catch {
            Warn "GitHub API loi: $($_.Exception.Message)"
        }

        # 2) Du phong: URL co dinh, khong phu thuoc API
        $urls.Add('https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip')

        $got = $false
        foreach ($u in $urls) {
            try {
                Step "Tai: $u"
                Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -TimeoutSec 300
                $got = $true
                break
            } catch {
                Warn "Tai that bai: $($_.Exception.Message)"
            }
        }

        if (-not $got) {
            Fail 'Khong tai duoc OpenSSH-Win64.zip'
        } else {
            try {
                $dst = Join-Path $env:ProgramFiles 'OpenSSH'
                if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
                Expand-Archive -LiteralPath $zip -DestinationPath $dst -Force
                $inner = Get-ChildItem -LiteralPath $dst -Directory | Select-Object -First 1
                if ($inner) {
                    Get-ChildItem -LiteralPath $inner.FullName | Move-Item -Destination $dst -Force
                    Remove-Item -LiteralPath $inner.FullName -Recurse -Force
                }
                & (Join-Path $dst 'install-sshd.ps1') | Out-Null
                $sshd = Get-SshdPath
                if ($sshd) { $installed = $true; Ok 'Da cai Win32-OpenSSH' }
                else { Fail 'Da giai nen nhung khong tim thay sshd.exe' }
            } catch {
                Fail "Cai OpenSSH that bai: $($_.Exception.Message)"
            }
        }
    }

    if (-not $installed) {
        Fail 'Khong cai duoc OpenSSH Server. Cai thu cong roi chay lai:'
        Write-Host '       Settings > Apps > Optional Features > OpenSSH Server'
        exit 1
    }
}

# -------------------------------------------------------------
# 2. Service sshd
# -------------------------------------------------------------
Step 'Bat service sshd...'
try {
    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if (-not $svc) { throw 'Service sshd khong ton tai sau khi cai.' }
    Set-Service -Name sshd -StartupType Automatic
    if ($svc.Status -ne 'Running') { Start-Service sshd }
    Start-Sleep -Milliseconds 800
    if ((Get-Service sshd).Status -eq 'Running') { Ok 'sshd dang chay va tu khoi dong cung Windows' }
    else { Fail 'sshd khong chay duoc.' }

    # Bat log su kien de phan tich tan cong sau nay
    & wevtutil.exe sl 'OpenSSH/Operational' /e:true 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok 'Da bat log OpenSSH/Operational' }
    else { Warn 'Khong bat duoc log OpenSSH/Operational (kiem tra thu cong)' }
} catch {
    Fail "Loi service sshd: $($_.Exception.Message)"
}

# -------------------------------------------------------------
# 3. Firewall
# -------------------------------------------------------------
if (-not $SkipFirewall) {
    Step "Mo firewall cho TCP $Port ..."
    try {
        $ruleName = "SSH bore tunnel TCP $Port"
        if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
                -Protocol TCP -LocalPort $Port -Profile Any | Out-Null
        }
        Ok "Firewall: da cho phep TCP $Port"
    } catch {
        Warn "Khong dung duoc NetFirewall: $($_.Exception.Message)"
        $netsh = "netsh advfirewall firewall add rule name=`"SSH bore tunnel $Port`" dir=in action=allow protocol=TCP localport=$Port"
        cmd /c $netsh | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok "Firewall: da them rule bang netsh" }
        else { Warn 'Khong them duoc rule firewall. Kiem tra thu cong.' }
    }
} else {
    Warn 'Bo qua firewall (--skip-firewall)'
}

# -------------------------------------------------------------
# 4. sshd_config
# -------------------------------------------------------------
Step 'Cau hinh sshd_config...'
# Bao dam service da tao file config lan dau
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { Fail 'sshd chua san sang.' }

$cfgDir = Join-Path $env:ProgramData 'ssh'
$cfg    = Join-Path $cfgDir 'sshd_config'

if (-not (Test-Path -LiteralPath $cfg)) {
    # Khoi dong 1 lan de service sinh config mac dinh
    try { Start-Service sshd; Start-Sleep -Seconds 1 } catch { }
    if (-not (Test-Path -LiteralPath $cfg)) {
        $cfgDir | ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
        @(
            "Subsystem`tsftp`tsftp-server.exe"
            "AuthorizedKeysFile`t.ssh/authorized_keys"
        ) | Set-Content -LiteralPath $cfg -Encoding ascii
        Warn 'sshd_config khong co san, da tao file toi thieu.'
    }
}

$backup = "$cfg.bore-ssh.bak"
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $cfg -Destination $backup -Force
    Ok "Backup: $backup"
}

$lines = @(Get-Content -LiteralPath $cfg)
$kept = New-Object System.Collections.Generic.List[string]
foreach ($line in $lines) {
    # Vo hieu cac dong cung loai de gia tri cua ta thang
    if ($line -match '^\s*(Port|PasswordAuthentication|PubkeyAuthentication|PermitEmptyPasswords|AllowTcpForwarding|UsePAM)\s+') {
        $kept.Add("# $line")
    } else {
        $kept.Add($line)
    }
}

# Chen o DAU file: tranh roi vao block "Match" o cuoi file
$header = @(
    '# ===== bore-ssh: bat dau =====',
    "Port $Port",
    'PasswordAuthentication yes',
    'PubkeyAuthentication yes',
    'PermitEmptyPasswords no',
    'AllowTcpForwarding yes',
    'LogLevel VERBOSE',
    'ClientAliveInterval 60',
    'ClientAliveCountMax 3',
    '# ===== bore-ssh: ket thuc =====',
    ''
)
$final = @($header) + $kept.ToArray()
[IO.File]::WriteAllLines($cfg, $final, (New-Object Text.UTF8Encoding($false)))

# sshd -t de kiem tra cu phap
$test = & $sshd -t 2>&1
if ($LASTEXITCODE -ne 0) {
    Fail "sshd_config loi, khoi phuc backup:"
    $test | ForEach-Object { Write-Host "       $_" }
    Copy-Item -LiteralPath $backup -Destination $cfg -Force
} else {
    Ok "sshd_config hop le (sshd -t)"
}

# Restart de ap dung
try {
    Restart-Service sshd -Force
    Start-Sleep -Milliseconds 800
    Ok 'Da restart sshd'
} catch {
    Fail "Restart sshd loi: $($_.Exception.Message)"
}

# -------------------------------------------------------------
# 5. Mat khau
# -------------------------------------------------------------
Write-Host ''
if ($NoPassword) {
    Warn 'Bo qua dat mat khau (--skip-password)'
} else {
    $acct = Get-LocalUser -Name $User -ErrorAction SilentlyContinue
    if (-not $acct) {
        Fail "User '$User' khong ton tai tren may nay."
    } else {
        if (-not $Password) {
            $chars = (48..57) + (65..90) + (97..122)
            $Password = 'Aa1!' + (-join ($chars | Get-Random -Count 12 | ForEach-Object { [char]$_ }))
        }
        $out = & net user $User $Password 2>&1
        if ($LASTEXITCODE -ne 0) {
            Fail "Khong dat duoc mat khau cho ${User}: $out"
        } else {
            Ok "Da dat mat khau cho user: $User"
            if (-not $acct.Enabled) {
                Enable-LocalUser -Name $User -ErrorAction SilentlyContinue
                Ok "Da bat lai tai khoan $User"
            }
            $script:NewPassword = $Password
            # Luu lai de lan sau in san lenh SSH day du (file da gitignore)
            try {
                $credFile = Join-Path (Split-Path -Parent $PSScriptRoot) '.ssh-password'
                $body = "SSH_USER=$User`r`nSSH_PASSWORD=$Password`r`n"
                [IO.File]::WriteAllText($credFile, $body, (New-Object Text.UTF8Encoding($false)))
                Ok 'Da luu .ssh-password (user + mat khau)'
            } catch {
                Warn "Khong luu duoc .ssh-password: $($_.Exception.Message)"
            }
        }
    }
}

# -------------------------------------------------------------
# 6. Kiem tra tu dong
# -------------------------------------------------------------
Write-Host ''
Write-Host '============================================================' -ForegroundColor White
Write-Host '  KIEM TRA TU DONG' -ForegroundColor White
Write-Host '============================================================' -ForegroundColor White

$probe = & $sshd -T 2>$null
if ($probe) { Ok 'sshd doc duoc cau hinh (sshd -T)' } else { Fail 'sshd -T that bai' }

if ($probe -match "(?m)^passwordauthentication yes") { Ok 'PasswordAuthentication = yes' }
else { Fail 'PasswordAuthentication != yes' }

if ($probe -match "(?m)^port $Port`$") { Ok "Port = $Port" }
else { Warn "Port trong config khong phai $Port" }

if ((Get-Service sshd).Status -eq 'Running') { Ok 'Service sshd RUNNING' }
else { Fail 'Service sshd khong chay' }

$open = $false
for ($i = 0; $i -lt 20; $i++) {
    if (Test-PortOpen $Port) { $open = $true; break }
    Start-Sleep -Milliseconds 500
}
if ($open) { Ok "Cong $Port dang LISTEN" } else { Fail "Cong $Port khong mo" }

# -------------------------------------------------------------
# 7. Ghi lai vao tunnel.conf
# -------------------------------------------------------------
if ($ConfPath) {
    Set-ConfValue -path $ConfPath -key 'SSH_PORT' -value "$Port"
    Set-ConfValue -path $ConfPath -key 'SSH_USER' -value "$User"
    Ok "Da ghi SSH_PORT=$Port, SSH_USER=$User vao tunnel.conf"
}

Write-Host ''
if ($script:NewPassword) {
    Write-Host "  User     : $User" -ForegroundColor White
    Write-Host "  Password : $($script:NewPassword)" -ForegroundColor Yellow
    Write-Host '  (luu mat khau nay lai, se dung de SSH)' -ForegroundColor DarkGray
}
Write-Host ''

if ($script:Failed -or (Get-Service sshd).Status -ne 'Running' -or -not $open) {
    Write-Host '[fail] Setup chua hoan tat, xem cac dong loi o tren.' -ForegroundColor Red
    exit 1
}

Write-Host '[ok] SSH SERVER DA SAN SANG' -ForegroundColor Green
exit 0
