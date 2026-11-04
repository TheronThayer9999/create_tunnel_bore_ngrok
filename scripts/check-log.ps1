# check-log.ps1
# Phan tich log SSH (OpenSSH/Operational) de phat hien scan / brute-force / flood.
#
#   powershell -File check-log.ps1 -Hours 24 -Port 2222
#
# Khong can quyen admin de doc, nhung can log da duoc bat:
#   wevtutil sl OpenSSH/Operational /e:true
[CmdletBinding()]
param(
    [int]$Hours = 24,
    [int]$Port = 2222,
    [int]$Top = 10
)

$ErrorActionPreference = 'Stop'
$LogName = 'OpenSSH/Operational'
$since = (Get-Date).AddHours(-$Hours)

function Line($label, $value) {
    Write-Host ("  {0,-24}: {1}" -f $label, $value)
}

try {
    $events = Get-WinEvent -FilterHashtable @{ LogName = $LogName; StartTime = $since } -ErrorAction Stop
} catch {
    Write-Host ''
    Write-Host '  [X] Khong doc duoc log OpenSSH/Operational.' -ForegroundColor Red
    Write-Host '      Bat log bang (PowerShell Admin):' -ForegroundColor Yellow
    Write-Host '        wevtutil sl OpenSSH/Operational /e:true' -ForegroundColor Yellow
    Write-Host '      Hoac chay: bore-ssh.bat setup  (script tu bat log)' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

$events = @($events)
$rxFailed   = [regex]'Failed password for (?:invalid user )?(?<user>\S+)'
$rxInvalid  = [regex]'Invalid user (?<user>\S+)'
$rxAccepted = [regex]'Accepted (?:password|publickey) for (?<user>\S+)'
$rxFrom     = [regex]'from (?<ip>\d{1,3}(?:\.\d{1,3}){3})'

$failed = 0; $invalid = 0; $accepted = 0
$ipFailed = @{}
$userFailed = @{}
$perMinute = @{}

foreach ($e in $events) {
    $m = $e.Message
    if (-not $m) { continue }

    $minute = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm')
    if (-not $perMinute.ContainsKey($minute)) { $perMinute[$minute] = 0 }
    $perMinute[$minute]++

    $ip = ''
    $fm = $rxFrom.Match($m)
    if ($fm.Success) { $ip = $fm.Groups['ip'].Value }

    if ($rxFailed.IsMatch($m)) {
        $failed++
        if ($ip) {
            if ($ipFailed.ContainsKey($ip)) { $ipFailed[$ip]++ } else { $ipFailed[$ip] = 1 }
        }
        $u = $rxFailed.Match($m).Groups['user'].Value
        if ($u) {
            if ($userFailed.ContainsKey($u)) { $userFailed[$u]++ } else { $userFailed[$u] = 1 }
        }
    }
    if ($rxInvalid.IsMatch($m)) { $invalid++ }
    if ($rxAccepted.IsMatch($m)) { $accepted++ }
}

$maxPerMinute = 0
foreach ($k in $perMinute.Keys) { if ($perMinute[$k] -gt $maxPerMinute) { $maxPerMinute = $perMinute[$k] } }

$established = 0
try {
    $c = Get-NetTCPConnection -LocalPort $Port -State Established -ErrorAction Stop
    $established = @($c).Count
} catch { }

Write-Host ''
Write-Host '============================================================' -ForegroundColor White
Write-Host ("  KIEM TRA LOG SSH - {0} gio qua" -f $Hours) -ForegroundColor White
Write-Host '============================================================' -ForegroundColor White
Line 'Tong so su kien'        $events.Count
Line 'Dang nhap thanh cong'   $accepted
Line 'Sai mat khau'           $failed
Line 'User khong ton tai'     $invalid
Line 'Ket noi/phut cao nhat'  $maxPerMinute
Line 'Ket noi dang mo'        $established

if ($ipFailed.Count -gt 0) {
    Write-Host '  ------------------------------------------------------------'
    Write-Host '  Top IP bi sai mat khau:' -ForegroundColor Yellow
    $ipFailed.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top | ForEach-Object {
        Write-Host ("    {0,-18} {1} lan" -f $_.Key, $_.Value)
    }
    Write-Host '  (Ket noi qua bore relay nen IP nguon la 127.0.0.1, khong phai IP that)' -ForegroundColor DarkGray
}

if ($userFailed.Count -gt 0) {
    Write-Host '  ------------------------------------------------------------'
    Write-Host '  Top user bi do (thu dang nhap):' -ForegroundColor Yellow
    $userFailed.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top | ForEach-Object {
        Write-Host ("    {0,-18} {1} lan" -f $_.Key, $_.Value)
    }
}

Write-Host '  ------------------------------------------------------------'

$verdict = 'Binh thuong: chua thay dau hieu tan cong.'
$color = 'Green'
if ($failed -ge 50 -or $invalid -ge 25) {
    $verdict = 'CANH BAO: dang bi brute-force / scan manh. Doi mat khau, dung SSH key, tat tunnel khi khong dung.'
    $color = 'Red'
} elseif ($failed -ge 10 -or $invalid -ge 5) {
    $verdict = 'Chu y: co dau hieu do quet. Nen dung mat khau manh hoac SSH key.'
    $color = 'Yellow'
}
if ($maxPerMinute -ge 60) {
    $verdict = 'CANH BAO: so ket noi/phut rat cao, co the dang bi flood.'
    $color = 'Red'
}

Write-Host ("  Ket luan: " + $verdict) -ForegroundColor $color
Write-Host '============================================================' -ForegroundColor White

Write-Host ''
Write-Host '  Goi y tang cuong:' -ForegroundColor Cyan
Write-Host '    - Dung SSH key thay mat khau (SSH_KEY trong tunnel.conf)'
Write-Host '    - Ghim port kho doan: REMOTE_PORT trong tunnel.conf'
Write-Host '    - Gioi han user duoc phep dang nhap, hoac doi mat khau dinh ky'
Write-Host '    - Chi mo tunnel khi can, dong khi xong'
Write-Host '    - KHONG dung fail2ban: qua bore moi ket noi la 127.0.0.1'
Write-Host ''
Write-Host '  Log day du: Event Viewer > Applications and Services Logs > OpenSSH > Operational'
Write-Host ''
