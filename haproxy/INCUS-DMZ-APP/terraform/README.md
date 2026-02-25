# Konsep Arsitektur DMZ (Demilitarized Zone)

Proyek ini mendemonstrasikan implementasi keamanan jaringan berlapis menggunakan arsitektur **DMZ (Demilitarized Zone)**. Sistem dibangun menggunakan virtualisasi **Incus** yang diprovisi oleh **Terraform** dan dikonfigurasi secara otomatis menggunakan **Ansible**.

## 🏗️ Topologi & Arsitektur Jaringan

Berikut adalah gambaran topologi dari sistem:

```text
                        +----------------------+
                        |       INTERNET       |
                        +----------+-----------+
                                   |
                                   v
 10.0.0.1 (NAT Bridge)  +----------+-----------+
----------------------->|     incusbr0 (IP)    |
                        +----------+-----------+
                                   |
+-------------------------------------------------------------------------+
|                              DMZ LAYER                                  |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  | DMZ Node (10.0.0.10)                                              |  |
|  |                                                                   |  |
|  |  +---------------+      +----------------+      +--------------+  |  |
|  |  |   Fail2Ban    |<-----|    HAProxy     |----->| ModSecurity  |  |  |
|  |  | (Host FW/Log) |      | (Reverse Proxy)| SPOA |   (WAF)      |  |  |
|  |  +---------------+      +-------+--------+      +--------------+  |  |
|  +---------------------------------|---------------------------------+  |
+------------------------------------|------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                           INTERNAL APP LAYER                            |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  | APP Node (10.0.0.11)                                              |  |
|  |                                                                   |  |
|  |  +---------------+                                                |  |
|  |  |  Echo Server  |                                                |  |
|  |  |  (Port: 3000) |                                                |  |
|  |  +---------------+                                                |  |
|  +-------------------------------------------------------------------+  |
+-------------------------------------------------------------------------+
```

Sistem terdiri dari dua Virtual Machine utama yang berjalan di atas bridge network internal Incus (`incusbr0` - `10.0.0.1/24` dengan NAT), yaitu:

1. **DMZ Node (Front-facing) (`10.0.0.10`)**
   Bertindak sebagai gerbang utama atau proxy server yang berhadapan langsung dengan traffic dari luar. Melindungi server backend dengan lapisan keamanan aktif dan pasif.
   
2. **APP Node (Backend Internal) (`10.0.0.11`)**
   Berjalan di zona belakang yang terisolasi. Traffic dari luar tidak dapat langsung menjangkau node ini. Hanya bisa diakses melalui proxy dari DMZ Node. Dalam lab ini, node APP menjalankan sebuah **Echo Server** di port `3000`.

## 🛡️ Komponen Keamanan pada Zona DMZ

Pada **DMZ Node**, beberapa layanan keamanan dan routing diimplementasikan (menggunakan Docker dan aplikasi host):

- **HAProxy (Load Balancer & Reverse Proxy):**
  - Menerima semua request masuk pada port HTTP (`80`) dan HTTPS (`443`).
  - Melakukan _SSL Termination_ (mendekripsi HTTPS) sebelum meneruskan request ke backend.
  - Melakukan _Auto-redirect_ dari HTTP ke HTTPS untuk memastikan enkripsi.
  - Mengarahkan traffic valid ke backend aplikasi (APP Node - 10.0.0.11:3000).

- **ModSecurity via SPOA (Web Application Firewall):**
  - Di-attach pada HAProxy menggunakan protokol SPOE (_Stream Processing Offload Engine_).
  - Melakukan inspeksi secara mendalam pada request HTTP/HTTPS untuk mendeteksi ancaman seperti SQL Injection, XSS, dan serangan web lainnya.
  - Jika request terdeteksi berbahaya oleh ModSecurity, HAProxy akan otomatis memblokir (memberikan response `403 Forbidden`).

- **Fail2ban (Active Intrusion Prevention):**
  - Memonitor file log HAProxy (`/var/log/haproxy.log`).
  - Jika ada host/IP yang mendapatkan pesan error `403 Forbidden` dari ModSecurity berulang kali (contoh: 3 kali dalam 60 detik), Fail2ban akan otomatis **memblokir penuh (banned)** IP tersebut di level *iptables* / _firewall_ selama periode tertentu (misal: 1 jam).
  - Ini mencegah _brute-force_ atau _DDoS_ ringan berlanjut ke layanan lainnya.

## 🚀 Alur Lalu Lintas (Traffic Flow)

1. **Client URL:** Pengguna atau attacker mengakses layanan via `https://echo.local`.
2. **DMZ HAProxy:** Traffic masuk ke DMZ IP (`10.0.0.10`). HAProxy menerima koneksi dan mendekripsi koneksi HTTPS.
3. **WAF Inspection:** HAProxy mengirimkan metadata request ke kontainer **ModSecurity** untuk inspeksi (lewat backend `spoe-modsecurity`).
4. **Decision:**
   - **Jika Malicious (Jahat):** ModSecurity menolak, HAProxy merespon `403 Forbidden`. Log ditulis. Jika diulang beberapa kali, Fail2ban memblokir total (_Banned IP_) di level Firewall Host DMZ.
   - **Jika Safe (Aman):** HAProxy meneruskan traffic secara transparan ke APP Node (`10.0.0.11:3000`).
5. **Backend Processing:** Node APP (Echo Server) memproses traffic yang sudah dianggap bersih, dan mengembalikan response ke klien melalui HAProxy.

## 🛠️ Ringkasan Teknologi

- **Infrastructure as Code:** `Terraform` (Membuat VM `DMZ` & `APP` + Network Bridge via Incus)
- **Configuration Management:** `Ansible` (Menginstall Docker, Fail2ban, ModSecurity, Echo Server secara otomatis)
- **Containerization:** `Docker Compose` (Memudahkan deployment HAProxy, ModSecurity SPOA, dan Echo Server)
- **Security & Proxy:** `HAProxy`, `ModSecurity (jcmoraisjr/modsecurity-spoa)`, `Fail2ban`, `Rsyslog`

Dengan desain DMZ ini, aplikasi utama (_backend_) sangat terlindungi dari paparan langsung di internet, dan segala bentuk anomali (seperti scanning, bad request, SQLi) direkam serta di-blok secara aktif dari lapisan paling luar.
