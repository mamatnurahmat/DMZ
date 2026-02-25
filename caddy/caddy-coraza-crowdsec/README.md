# DMZ Caddy-Coraza + CrowdSec

DMZ (Demilitarized Zone) dengan **3-layer security**:
1. **CrowdSec** — IP reputation & behavior-based detection (IPS)
2. **Coraza WAF** — OWASP CRS payload inspection
3. **Caddy** — Reverse proxy dengan auto-HTTPS

## Arsitektur

```
                    ┌───────────────────────────────────────────────────────┐
                    │                     DMZ Zone                         │
                    │                                                      │
  Internet          │   ┌─────────────────────────────────────────────┐    │
  ─────────────────►│   │            Caddy Reverse Proxy              │    │
  Request           │   │                                             │    │
                    │   │  ┌──────────────┐   ┌───────────────────┐  │    │
                    │   │  │  CrowdSec    │   │   Coraza WAF      │  │    │
                    │   │  │  Bouncer     │──►│   OWASP CRS       │  │    │    Internal
                    │   │  │  (IP Check)  │   │   (Payload Check) │──┼───►│    Backend
                    │   │  └──────┬───────┘   └───────────────────┘  │    │
                    │   │         │                                   │    │
                    │   └─────────┼───────────────────────────────────┘    │
                    │             │                                        │
                    │   ┌─────────▼───────────────────────────────────┐    │
                    │   │         CrowdSec LAPI                      │    │
                    │   │  - Parse access logs                       │    │
                    │   │  - Behavior detection                      │    │
                    │   │  - Crowdsourced IP blocklist                │    │
                    │   │  - AppSec (virtual patching)               │    │
                    │   └────────────────────────────────────────────-┘    │
                    │                                                      │
  ◄─────────────────│   Response: 200 OK / 403 Forbidden                   │
                    └───────────────────────────────────────────────────────┘
```

### Perbedaan Coraza WAF vs CrowdSec

| Fitur | Coraza WAF | CrowdSec |
|-------|-----------|----------|
| **Tipe** | WAF (Web Application Firewall) | IPS (Intrusion Prevention System) |
| **Deteksi** | Pola payload (regex rules) | Perilaku + IP reputation |
| **Rules** | OWASP CRS (static rules) | Crowdsourced + community scenarios |
| **Scope** | Per-request inspection | Per-IP tracking over time |
| **Contoh** | Blokir `' OR 1=1` di query | Ban IP yang 10x gagal login dalam 1 menit |

### Alur Request

1. Request masuk ke **Caddy** (port 80/443)
2. **CrowdSec Bouncer** cek apakah IP source ada di daftar ban
3. Jika **IP banned** → response `403 Forbidden`
4. **Coraza WAF** inspeksi payload terhadap **OWASP CRS rules**
5. Jika **serangan terdeteksi** → response `403 Forbidden`
6. Jika **aman** → request diteruskan ke backend service

## Struktur Direktori

```
caddy-coraza-crowdsec/
├── caddy/
│   └── Dockerfile              # Build Caddy + Coraza + CrowdSec Bouncer
├── crowdsec/
│   └── acquis.yaml             # CrowdSec acquisition config
├── ruleset/
│   ├── coraza.conf             # Konfigurasi Coraza WAF
│   └── owasp-crs/              # OWASP Core Rule Set
├── data/                        # (gitignored) Caddy certs & data
├── config/                      # (gitignored) Caddy auto-config
├── audit/                       # (gitignored) WAF audit logs
├── logs/                        # (gitignored) Caddy access logs → CrowdSec
├── Caddyfile                    # Routing + WAF + CrowdSec config
├── docker-compose.yml           # Caddy + CrowdSec + whoami
├── .env                         # (gitignored) CrowdSec API key
├── test_waf.sh                  # Test Coraza WAF
├── test_crowdsec.sh             # Test CrowdSec ban/unban
└── .gitignore
```

## Quick Start

### 1. Setup CrowdSec API Key

Jalankan pertama kali tanpa Caddy untuk generate bouncer key:

```bash
# Start CrowdSec dulu
docker compose up -d crowdsec

# Generate bouncer API key
docker compose exec crowdsec cscli bouncers add caddy-bouncer

# Copy API key yang di-generate, lalu update .env
echo "CROWDSEC_API_KEY=<paste-key-disini>" > .env
```

### 2. Copy OWASP CRS Rules

```bash
# Clone coreruleset
git clone https://github.com/coreruleset/coreruleset.git -b v4.23.0

# Copy rules ke ruleset
cp coreruleset/rules/* ruleset/owasp-crs/
cp coreruleset/crs-setup.conf.example ruleset/owasp-crs/crs-setup.conf

# Cleanup
rm -rf coreruleset
```

### 3. Build & Jalankan

```bash
# Build & jalankan semua service
docker compose up --build -d
```

### 4. Tambahkan DNS Lokal

```
# /etc/hosts
127.0.0.1 whoami.local
```

### 5. Test

```bash
# Test akses normal
curl http://whoami.local

# Test WAF (Coraza)
./test_waf.sh http://whoami.local

# Test CrowdSec
./test_crowdsec.sh http://whoami.local
```

## CrowdSec Management

### Decisions (Ban/Unban)

```bash
# Lihat daftar ban aktif
docker compose exec crowdsec cscli decisions list

# Ban IP manual (5 menit)
docker compose exec crowdsec cscli decisions add -i 192.168.1.100 -d 5m -t ban

# Unban IP
docker compose exec crowdsec cscli decisions delete --ip 192.168.1.100
```

### Alerts

```bash
# Lihat alerts
docker compose exec crowdsec cscli alerts list

# Detail alert
docker compose exec crowdsec cscli alerts inspect <ALERT_ID>
```

### Bouncer

```bash
# Lihat daftar bouncer
docker compose exec crowdsec cscli bouncers list

# Tambah bouncer baru
docker compose exec crowdsec cscli bouncers add <nama>
```

### Metrics

```bash
# Lihat metrics acquisition (log parsing)
docker compose exec crowdsec cscli metrics show acquisition

# Lihat semua metrics
docker compose exec crowdsec cscli metrics
```

## Menambah Domain Baru

Edit `Caddyfile` dan tambahkan blok baru:

```caddyfile
app.example.com {
    log
    route {
        crowdsec
        coraza_waf {
            load_owasp_crs
            directives `
                Include /ruleset/coraza.conf
                Include /ruleset/owasp-crs/crs-setup.conf
                Include /ruleset/owasp-crs/rules/*.conf
                SecRuleEngine On
            `
        }
        reverse_proxy backend-service:8080
    }
}
```

Reload Caddy:

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

### CrowdSec Collections

Collections yang terinstall otomatis:

| Collection | Fungsi |
|-----------|--------|
| `crowdsecurity/caddy` | Parser untuk Caddy access logs |
| `crowdsecurity/http-cve` | Deteksi eksploitasi CVE pada HTTP |
| `crowdsecurity/whitelist-good-actors` | Whitelist bot baik (Googlebot, dll) |
| `crowdsecurity/appsec-virtual-patching` | Virtual patching untuk vulnerability umum |
| `crowdsecurity/appsec-generic-rules` | Rules umum AppSec (blocking `.env`, `.git`, dll) |

## Custom Caddy Image

Image dibuild dari `caddy/Dockerfile` dengan 3 module:

```dockerfile
FROM caddy:2.9-builder AS builder
WORKDIR /app
RUN xcaddy build \
    --with github.com/corazawaf/coraza-caddy/v2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@main \
    --with github.com/hslatman/caddy-crowdsec-bouncer/appsec@main

FROM caddy:2.9
COPY --from=builder /app/caddy /usr/bin/caddy
```

| Module | Fungsi |
|--------|--------|
| `coraza-caddy/v2` | Coraza WAF engine untuk Caddy |
| `caddy-crowdsec-bouncer/http` | CrowdSec bouncer — cek IP decisions |
| `caddy-crowdsec-bouncer/appsec` | CrowdSec AppSec — forward request ke LAPI |
