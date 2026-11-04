<#
    defender-exclude.ps1
    Them mot thu muc vao danh sach loai tru cua Windows Defender.

    Dung cho bore.exe: Defender bao nham binary tunnel Rust la
    "Trojan:Win32/Kepavll!rfn" va cach ly file ngay khi chay.

    Chay can quyen Administrator (tu kiem tra, khong dung #Requires).

    Exit code: 0 = da loai tru, 1 = loi, 2 = thieu quyen, 3 = khong co Defender
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    if (-not (Test-Admin)) {
        Say ''
        Say '  [X] Can quyen Administrator (chay PowerShell as Administrator).' 'Red'
        exit 2
    }

    if (-not (Get-Command Add-MpPreference -ErrorAction SilentlyContinue)) {
        Say ''
        Say '  [i] May nay khong co Windows Defender - khong can loai tru.' 'Yellow'
        exit 3
    }

    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
    }

    $excel = @((Get-MpPreference).ExclusionPath)
    if ($excel -contains $full) {
        Say "  [ok] Defender da loai tru: $full" 'Green'
        exit 0
    }

    Add-MpPreference -ExclusionPath $full

    $excel = @((Get-MpPreference).ExclusionPath)
    if ($excel -contains $full) {
        Say "  [ok] Da loai tru Defender: $full" 'Green'
        exit 0
    }

    Say "  [X] Khong them duoc loai tru (Tamper Protection hoac Group Policy dang chan)." 'Red'
    exit 1
}
catch {
    Say ''
    Say ('  [X] Loi khi them loai tru: ' + $_.Exception.Message) 'Red'
    exit 1
}
