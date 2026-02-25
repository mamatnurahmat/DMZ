# Panduan Fail2ban untuk HAProxy & ModSecurity

Dokumen ini menjelaskan bagaimana Fail2ban diintegrasikan dengan HAProxy dan ModSecurity pada environment DMZ (10.0.0.10), serta bagaimana melakukan skenario pengujian serangan hingga IP penyerang diblokir.

## 1. Arsitektur Singkat dan Konfigurasi
* **HAProxy & ModSecurity**: Keduanya berjalan sebagai container Docker. HAProxy menerima permintaan (request) dan ModSecurity mengevaluasinya. Jika ModSecurity mendeteksi ancaman (seperti *SQL Injection* atau *XSS*), HAProxy menolak *request* tersebut dengan HTTP Status **403 Forbidden**.
* **Rsyslog**: HAProxy dikonfigurasi untuk mengirim log ke `/dev/log` Host. Rsyslog pada Host menangkap log tersebut dan menyimpannya di `/var/log/haproxy.log`.
* **Fail2ban**: Mengawasi `/var/log/haproxy.log`. Berdasarkan konfigurasi, Fail2ban akan melakukan *banning* (pemblokiran) pada IP penyerang jika memenuhi kriteria berikut:
  - **maxretry**: 3 kali percobaan (serangan)
  - **findtime**: Dalam jendela waktu 60 detik
  - **bantime**: Jika melanggar, IP diblokir selama 3600 detik (1 Jam)
  - **Action**: Menggunakan `iptables-allports[chain="DOCKER-USER"]` untuk memastikan *drop rules* berfungsi sebelum traffic masuk ke Docker network.

---

## 2. Skenario Pengujian (Serangan & Pemblokiran)

Untuk memastikan mekanisme ini berjalan, Anda bisa melakukan simulasi serangan dari mesin lain (atau dari mesin Host asal Anda memiliki *route* ke IP DMZ 10.0.0.10).

### Langkah 1: Persiapan Pantau Log di Node DMZ
Buka dua terminal SSH ke mesin DMZ (`10.0.0.10`) untuk memantau log secara real-time.

**Terminal 1: Pantau Log HAProxy**
```bash
tail -f /var/log/haproxy.log | grep "403"
```

**Terminal 2: Pantau Log Fail2ban**
```bash
tail -f /var/log/fail2ban.log
```

### Langkah 2: Lakukan Serangan (Simulasi XSS / SQLi)
Dari mesin klien (laptop Anda atau VM lain, pastikan **TIDAK** menjalankan curl dari dalam server DMZ itu sendiri agar IP yang diblokir adalah IP eksternal):

Jalankan perintah `curl` dengan payload *SQL Injection* atau *Directory Traversal* berturut-turut.
```bash
# Serangan 1
curl -k -H "Host: echo.local" "https://10.0.0.10/?id=1' OR '1'='1"

# Serangan 2
curl -k -H "Host: echo.local" "https://10.0.0.10/?exec=/bin/bash"

# Serangan 3 (Akan memicu Fail2ban untuk melakukan Banning)
curl -k -H "Host: echo.local" "https://10.0.0.10/?q=<script>alert('xss')</script>"
```
*Catatan: Pada tahap ini, ModSecurity akan memblokir request dan HAProxy mengembalikan respon HTTP 403.*

### Langkah 3: Verifikasi IP Terblokir

Setelah serangan ke-3, Fail2ban akan mendeteksi batas *maxretry* dan langsung memblokir IP Anda.

1. **Coba akses situs secara normal** setelah pemblokiran:
   ```bash
   curl -k -H "Host: echo.local" "https://10.0.0.10/"
   ```
   *Ekspektasi: Koneksi akan menggantung (Timeout) atau direject (Connection Refused), karena iptables telah menge-drop traffic Anda.*

2. **Cek Status Jail di DMZ**:
   Di mesin DMZ, jalankan perintah fail2ban-client:
   ```bash
   sudo fail2ban-client status haproxy-modsec
   ```
   *Output akan menunjukkan jumlah percobaan gagal dan daftar IP yang saat ini berstatus Banned.*

3. **Cek Rules Iptables di DMZ**:
   ```bash
   sudo iptables -nL DOCKER-USER
   ```
   *Anda akan melihat aturan REJECT/DROP untuk IP penyerang pada chain DOCKER-USER.*

---

## 3. Manajemen Fail2ban (Unban IP)

Jika Anda ingin membuka kembali blokir IP yang sebelumnya terkena ban (karena sedang *testing*), gunakan perintah berikut dari dalam mesin DMZ:

**Melihat IP yang di-banned:**
```bash
sudo fail2ban-client status haproxy-modsec
```

**Membuka blokir (Unban) IP tertentu:**
*(Gantikan `<IP_ADDRESS>` dengan IP Anda yang terblokir)*
```bash
sudo fail2ban-client set haproxy-modsec unbanip <IP_ADDRESS>
```

**Membuka semua IP yang terblokir:**
```bash
sudo fail2ban-client unban --all
```

---
*Selesai. Setup ini memastikan layanan HAProxy Load Balancer DMZ Anda memiliki lapisan otomatisasi perlindungan aktif menggunakan Fail2ban.*
