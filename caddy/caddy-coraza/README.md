# DMZ Caddy-Coraza WAF

DMZ (Demilitarized Zone) menggunakan **Caddy** sebagai reverse proxy dan **Coraza WAF** (Web Application Firewall) dengan **OWASP CRS** (Core Rule Set) untuk proteksi aplikasi web.

## Konsep Arsitektur DMZ

```
                    ┌──────────────────────────────────────────────┐
                    │                 DMZ Zone                     │
                    │                                              │
  Internet          │   ┌─────────────────────┐                   │    Internal Network
  ─────────────────►│   │   Caddy + Coraza    │                   │
  Request           │   │                     │   ┌────────────┐  │
                    │   │  ┌───────────────┐  │   │            │  │
                    │   │  │  OWASP CRS    │  ├──►│  Backend   │  │
                    │   │  │  Rules        │  │   │  Services  │  │
                    │   │  └───────────────┘  │   │            │  │
                    │   │                     │   └────────────┘  │
  ◄─────────────────│   │  Reverse Proxy      │                   │
  Response          │   └─────────────────────┘                   │
  (Clean/403)       │                                              │
                    └──────────────────────────────────────────────┘
```

### Komponen

| Komponen | Fungsi |
|----------|--------|
| **Caddy** | Reverse proxy dengan auto-HTTPS, HTTP/2, konfigurasi sederhana |
| **Coraza** | WAF engine open-source, kompatibel dengan ModSecurity rules |
| **OWASP CRS** | Ruleset standar industri untuk deteksi serangan web (SQLi, XSS, LFI, RCE, dll) |

### Alur Request

1. Request masuk ke **Caddy** (port 80/443)
2. **Coraza WAF** memproses request terhadap **OWASP CRS rules**
3. Jika **terdeteksi serangan** → response `403 Forbidden`
4. Jika **aman** → request diteruskan ke backend service via reverse proxy

### Serangan yang Diblokir

- **SQL Injection** — `' OR 1=1 --`
- **Cross-Site Scripting (XSS)** — `<script>alert('xss')</script>`
- **Local File Inclusion (LFI)** — `../../etc/passwd`
- **Remote Code Execution (RCE)** — `; ls -la`
- **Remote File Inclusion (RFI)** — `http://evil.com/shell.txt`
- **Log4j / JNDI Injection**
- dan banyak lagi...

## Struktur Direktori

```
caddy-coraza/
├── caddy/
│   └── Dockerfile              # Build custom Caddy + Coraza
├── ruleset/
│   ├── coraza.conf             # Konfigurasi Coraza WAF
│   └── owasp-crs/             # OWASP Core Rule Set
├── data/                       # (gitignored) Caddy certs & data
├── config/                     # (gitignored) Caddy auto-config
├── audit/                      # (gitignored) WAF audit logs
├── Caddyfile                   # Konfigurasi routing & WAF
├── docker-compose.yml          # Service definitions
├── test_waf.sh                 # Test WAF (multi-payload)
├── test_xss.sh                 # Test XSS spesifik
└── .gitignore
```

## Quick Start

### 1. Build & Jalankan

```bash
# Build image caddy + coraza
docker compose build

# Jalankan semua service
docker compose up -d
```

### 2. Tambahkan DNS Lokal

Tambahkan entry ke `/etc/hosts`:

```
127.0.0.1 whoami.local
```

### 3. Test Akses Normal

```bash
# Request normal — harus return info dari whoami
curl -H "Host: whoami.local" http://localhost
```

Output yang diharapkan:
```
Hostname: <container-id>
IP: 172.x.x.x
RemoteAddr: 172.x.x.x:xxxxx
GET / HTTP/1.1
Host: whoami.local
...
```

### 4. Test WAF Blocking

```bash
# Test XSS — harus return 403
curl -I "http://whoami.local/?q=<script>alert('xss')</script>"

# Test SQL Injection — harus return 403
curl -I "http://whoami.local/?id=1' OR '1'='1"

# Test LFI — harus return 403
curl -I "http://whoami.local/?file=../../etc/passwd"

# Jalankan semua test
./test_waf.sh http://whoami.local
./test_xss.sh http://whoami.local
```

## Menambah Domain Baru

Edit `Caddyfile` dan tambahkan blok baru:

```caddyfile
app.example.com {
    coraza_waf {
        load_owasp_crs
        directives `
            Include /ruleset/coraza.conf
            Include /ruleset/owasp-crs/crs-setup.conf
            Include /ruleset/owasp-crs/rules/*.conf
            SecRuleEngine On
            SecAuditLog /audit/waf-audit.log
            SecAuditEngine RelevantOnly
        `
    }
    reverse_proxy backend-service:8080
}
```

Kemudian reload Caddy:

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Konfigurasi WAF

### Mode Engine

Di `ruleset/coraza.conf`, ubah mode WAF:

| Mode | Fungsi |
|------|--------|
| `SecRuleEngine On` | Blocking mode — serangan diblokir (production) |
| `SecRuleEngine DetectionOnly` | Detection mode — log saja, tidak diblokir (testing) |

### Audit Log

Log audit WAF tersimpan di `./audit/waf-audit.log`. Untuk melihat:

```bash
# Lihat log real-time
docker compose exec caddy tail -f /audit/waf-audit.log
```

## Custom Caddy Image

Image `newrahmat/caddy:2.7.4-coraza` dibuild dari `caddy/Dockerfile`:

```dockerfile
FROM caddy:2.7.4-builder AS builder
WORKDIR /app
RUN xcaddy build --output caddy \
    --with github.com/corazawaf/coraza-caddy/v2@latest

FROM caddy:2.7.4
COPY --from=builder /app/caddy /usr/bin/caddy
```

Ini menambahkan plugin **coraza-caddy** ke binary Caddy standar.
