# SSH over bore — vào Windows Server VM sau NAT

Bộ script tự động dựng **SSH server + tunnel ra ngoài** cho một máy ảo không có IP public (Windows Server, Linux, Colab, Docker…), rồi in sẵn lệnh SSH để bạn kết nối từ bất kỳ đâu.

```
   Máy ảo Windows Server          bore relay              Máy của bạn
   (sau NAT, không IP public)     bore.pub                (bất kỳ đâu)
   ┌──────────────────────┐      ┌──────────┐      ┌──────────────────────┐
   │ sshd :2222           │─────▶│ :51234   │◀─────│ ssh -p 51234         │
   │ bore local 2222 ...  │ thoát│  (public)│      │ user@bore.pub        │
   └──────────────────────┘  ra  └──────────┘      └──────────────────────┘
```

Tunnel được **phát ra từ chính máy ảo** (outbound), nên không cần mở port trên router, không cần IP tĩnh, không cần VPN. Chỉ mở khi cần — đóng cửa sổ là tunnel tắt, không cài service chạy nền.

Mỗi nền tảng chỉ có **một file cần chạy**: `bore-ssh.bat` (Windows) hoặc `bore-ssh.sh` (Linux/macOS).

---

## 1. Yêu cầu

| Thành phần | Ghi chú |
|---|---|
| Máy Windows Server VM | Windows Server 2019+ (khuyến nghị) hoặc 2016 (tự fallback Win32-OpenSSH); có internet ra ngoài, quyền Administrator |
| PowerShell 5.1 | Có sẵn trên Windows |
| `curl.exe`, `tar.exe` | Có sẵn trên Windows 10/Server 2019+ (dùng để tải bore) |
| Máy client | Có `ssh` (Windows 10+, Linux, macOS) |
| bore | Script tự tải về `bin/` |

---

## 2. Bắt đầu nhanh trên VM Windows Server

```bat
git clone <repo-url> D:\script_tunnel_ssh
cd D:\script_tunnel_ssh
bore-ssh.bat setup
```

Hoặc **double-click `bore-ssh.bat`** rồi chọn `[1] Setup SSH server + mo tunnel` — script tự xin quyền Administrator qua UAC.

Lệnh `setup` chạy tuần tự:

1. Tải `bore.exe` vào `bin\` (nếu chưa có)
2. Cài **OpenSSH Server** (Windows Capability, fallback Win32-OpenSSH từ GitHub)
3. Bật service `sshd` (Automatic + Start)
4. Mở firewall cho cổng SSH
5. Sửa `sshd_config`: `Port 2222`, `PasswordAuthentication yes` (có backup)
6. Đặt mật khẩu cho user (tự sinh nếu không truyền `--password`)
7. **Tự kiểm tra**: `sshd -T`, service RUNNING, cổng đang LISTEN
8. Mở bore tunnel, đọc cổng public, in ra lệnh SSH

Kết quả in ra (phần cuối):

```
[ok] SSH SERVER DA SAN SANG

  User     : Administrator
  Password : Aa1!x8Kp2mQz7

  ============================================================
     TUNNEL DANG MO
  ============================================================
     Cong khai : bore.pub:51234
     SSH vao   : ssh -p 51234 Administrator@bore.pub
  ============================================================

  [i] Tunnel dang chay. Nhan phim bat ky de DUNG tunnel va thoat.
```

> **Lưu ý:** mật khẩu do script sinh và chỉ hiện một lần. Lưu lại ngay.
> Giữ cửa sổ này mở — đóng cửa sổ là tunnel tắt.

---

## 3. SSH vào máy ảo từ máy khác

```bash
ssh -p 51234 Administrator@bore.pub
```

Lệnh trên gồm 3 phần:

| Phần | Nghĩa | Lấy ở đâu |
|---|---|---|
| `Administrator` | user Windows **trên máy ảo** | tài khoản bạn đăng nhập Windows (hoặc `--user NAME`) |
| `bore.pub` | relay của bore, **không phải** máy ảo | cố định |
| `-p 51234` | cổng public bore cấp | in ra khi mở tunnel |

bore **không có UUID/token**: định danh duy nhất của tunnel là số port. Mật khẩu là mật khẩu của tài khoản Windows đó.

### Gõ tắt để không phải nhớ port (khuyến nghị)

**Cách 1 — ghim port** trong `tunnel.conf`:

```ini
REMOTE_PORT=51234
```

Từ đó mỗi lần chạy vẫn là `ssh -p 51234 user@bore.pub`, không đổi nữa.

**Cách 2 — alias trong SSH config** (máy client), sửa `~/.ssh/config`:

```
Host vm
    HostName bore.pub
    Port 51234
    User Administrator
    ServerAliveInterval 30
```

Sau đó chỉ cần gõ:

```bash
ssh vm
```

Port đổi thì sửa đúng 1 dòng `Port`. Trên Windows file này ở `%USERPROFILE%\.ssh\config`.

**Cách 3 — dùng script client** (đọc lại port lần chạy trước):

```bat
bore-ssh.bat c        :: Windows
```
```bash
./bore-ssh.sh c       # Linux / macOS
```

### Lưu ý về thời gian dùng

Script **không** cài service/scheduled task: tunnel chỉ sống trong cửa sổ đang chạy. Dùng vài tiếng rồi đóng là hợp lý, không cần dọn dẹp gì. Nếu muốn chạy nền lâu dài mới cần Task Scheduler / `nohup` / `tmux`.

---

## 4. Chạy lại khi SSH đã cài sẵn

Không cần setup lại, chỉ mở tunnel:

```bat
bore-ssh.bat s        :: Windows (s = server)
```
```bash
./bore-ssh.sh s       # Linux / macOS
```

Xem trước lệnh mà không chạy thật:

```bat
bore-ssh.bat s --dry-run
```

---

## 5. Cấu hình — `tunnel.conf`

`bore-ssh.bat setup` tự tạo `tunnel.conf` từ file mẫu và tự ghi `SSH_PORT` + `SSH_USER`. Muốn sửa tay:

```bat
copy tunnel.conf.example tunnel.conf
```

| Key | Ý nghĩa | Mặc định |
|---|---|---|
| `BORE_SERVER` | Relay server: `bore.pub` hoặc `host:7835` | `bore.pub` |
| `SSH_PORT` | Cổng SSH nội bộ của máy chạy server | `2222` |
| `SSH_USER` | User in ra trong lệnh SSH | trống |
| `SSH_KEY` | Private key cho chế độ client | trống |
| `REMOTE_PORT` | Xin bore cấp cổng public cố định | trống = ngẫu nhiên |
| `BORE_BIN` | Đường dẫn `bore` binary | `bin/bore(.exe)` |
| `BORE_ARGS` | Tham số thêm cho `bore local` | trống |

Ví dụ expose SSH của **một máy khác trong LAN** qua máy đang chạy script:

```ini
BORE_ARGS=--local-host 192.168.1.50
```

Ví dụ dùng relay riêng có secret:

```ini
BORE_SERVER=bore.example.com:7835
BORE_ARGS=--secret my-secret
```

---

## 6. Tùy chọn dòng lệnh — `bore-ssh.bat setup`

| Tùy chọn | Tác dụng |
|---|---|
| `--port N` | Cổng SSH nội bộ (mặc định 2222) |
| `--password P` | Đặt mật khẩu, không tự sinh |
| `--user NAME` | User dùng để SSH (mặc định user đang chạy) |
| `--ssh-only` | Chỉ setup SSH, không mở tunnel |
| `--skip-password` | Không đổi mật khẩu hiện tại |
| `--dry-run` | In các bước, không thay đổi hệ thống |

Lệnh tắt: `st` = setup, `s` = server, `c` = client, `i` = install, `l` = logs.

---

## 7. Bản Linux / Colab / Docker

```bash
chmod +x bore-ssh.sh
./bore-ssh.sh setup
```

Script tương đương bản Windows: cài `openssh-server` theo distro, ghi drop-in `/etc/ssh/sshd_config.d/99-bore-tunnel.conf`, đặt mật khẩu, bật sshd, tự kiểm tra rồi mở bore và in lệnh SSH.

```bash
./bore-ssh.sh setup --port 2222 --password 'MySecurePass123'
./bore-ssh.sh setup --ssh-only          # chỉ bật SSH
./bore-ssh.sh setup --dry-run           # xem trước
```

Trên Colab/Docker (không có systemd) script tự chạy `sshd` trực tiếp và dùng cổng `2222`.

---

## 8. Bảo mật — đọc trước khi dùng

- `bore.pub` là **relay công khai**: ai biết `bore.pub:PORT` đều chạm được `sshd` của bạn. SSH vẫn yêu cầu đăng nhập, nhưng hãy:
  - dùng mật khẩu mạnh (script sinh 16 ký tự), hoặc tốt hơn là **SSH key**;
  - tránh để tunnel chạy 24/7 khi không dùng;
  - cổng public ngẫu nhiên cũng là một lớp giảm dò quét.
- Script **bật** `PermitRootLogin yes` và `PasswordAuthentication yes` (Linux) / mở firewall + password auth (Windows) để tiện dùng. Đây là đánh đổi bảo mật — với máy production, hãy dùng key và tắt password auth.
- Cần riêng tư hơn: tự host `bore server --secret ...` rồi cấu hình `BORE_SERVER` + `BORE_ARGS=--secret ...`.
- Mọi thay đổi cấu hình đều có backup: `sshd_config.bore-ssh.bak` (Windows: `C:\ProgramData\ssh\sshd_config.bore-ssh.bak`).

---

## 9. Sự cố thường gặp

| Triệu chứng | Cách xử lý |
|---|---|
| Windows Defender báo `bore.exe` là virus và xóa file | False positive phổ biến với binary tunnel Rust. Thêm `bin\` vào danh sách loại trừ, hoặc tải bore từ GitHub rồi bỏ vào `bin\` |
| `Khong mo duoc tunnel` + log báo port in use | `REMOTE_PORT` đã bị người khác dùng → đổi số khác hoặc để trống |
| `sshd` không chạy | Windows: `Get-Service sshd` / `Restart-Service sshd`; Linux: xem `/tmp/sshd-bore.log` |
| Kết nối tới nhưng `Permission denied` | Kiểm tra user tồn tại + đã bật, mật khẩu đúng, `PasswordAuthentication yes` |
| Cổng public đổi liên tục | Đặt `REMOTE_PORT` cố định trong `tunnel.conf` |
| Đóng cửa sổ là mất tunnel | Đúng thiết kế. Muốn chạy nền: Task Scheduler (Windows) hoặc `nohup`/`tmux` (Linux) |
| Còn tiến trình bore sót | Windows: `taskkill /IM bore.exe /F` — Linux: `pkill -x bore` |
| Cần debug kết nối | `ssh -vvv -p PORT user@bore.pub` |

Kiểm tra nhanh phía server:

```bat
sshd -T | findstr /I "port passwordauth"
netstat -ano | findstr :2222
```

---

## 10. Log & phát hiện tấn công

Vì port public nằm trên `bore.pub`, **sẽ có bot quét**. Script bật sẵn log và có sẵn lệnh kiểm tra.

| Nơi lưu log | Nội dung |
|---|---|
| Windows: Event Log `OpenSSH/Operational` | mọi kết nối, đăng nhập sai, user không tồn tại |
| `sshd_config` → `LogLevel VERBOSE` | ghi cả tên user bị thử |
| `.bore-ssh.log` | log của bore (kết nối qua relay) |

Xem nhanh:

```bat
bore-ssh.bat logs              :: 24 giờ gần nhất
bore-ssh.bat logs --hours 6    :: 6 giờ gần nhất
```
```bash
./bore-ssh.sh logs
```

Kết quả gồm: số lần sai mật khẩu, user bị dò, top IP, **số kết nối/phút cao nhất** (dấu hiệu flood), và kết luận bình thường / bị dò / bị flood.

> ⚠️ **Quan trọng:** qua bore, mọi kết nối đến sshd đều từ `127.0.0.1`, nên log **không cho biết IP thật** của kẻ tấn công. Bạn vẫn thấy được số lần, user bị thử và tốc độ — đủ để biết máy đang bị dò hay bị flood.

Cách giảm rủi ro thật sự (không chỉ xem log):

- dùng **SSH key** thay mật khẩu;
- ghim port khó đoán (`REMOTE_PORT`) và đổi khi cần;
- giới hạn user được đăng nhập;
- chỉ mở tunnel khi dùng, đóng khi xong;
- **không** dùng fail2ban ở đây — nó sẽ thấy `127.0.0.1` và tự chặn tunnel của bạn.

Muốn biết IP thật thì phải tự host bore sau một reverse proxy có PROXY protocol, hoặc dùng Cloudflare Tunnel.

---

## 11. Cấu trúc repo

```
.
├── bore-ssh.bat                  # [Windows] entry duy nhất: menu + setup + tunnel + client
├── bore-ssh.sh                   # [Linux]   entry duy nhất: menu + setup + tunnel + client
├── scripts/
│   ├── setup-sshd-windows.ps1    #   cài/cấu hình OpenSSH Server (Windows)
│   ├── setup-ssh-linux.sh        #   cài/cấu hình sshd (Linux/Colab/Docker)
│   ├── check-log.ps1             #   phân tích log + phát hiện tấn công (Windows)
│   └── check-log.sh              #   phân tích log + phát hiện tấn công (Linux)
├── tunnel.conf.example           # mẫu cấu hình (copy thành tunnel.conf)
└── bin/                          # bore binary được tải tự động (gitignore)
```

Luồng chạy:

```
bore-ssh.bat setup
  └─ scripts/setup-sshd-windows.ps1   (cài + cấu hình + tự kiểm tra)
  └─ mở tunnel, đọc port, in lệnh SSH
```

---

## License

MIT — dùng thoải mái, tự chịu trách nhiệm về cấu hình bảo mật của máy mình.
