# TTN CUPS Configuration

LoRa gateway configuration for The Things Network using CUPS protocol.

## Quick Start

```bash
# From repository root
./setup-gateway.sh
```

The setup script handles building, EUI detection, and credential configuration.

## Manual Start

```bash
./start-station.sh        # std variant
./start-station.sh -d     # debug variant
```

## Files

| File | Description |
|------|-------------|
| `start-station.sh` | Launch script |
| `reset_lgw.sh` | GPIO reset (auto-detects Pi model) |
| `rinit.sh` | Radio initialization |
| `station.conf.template` | Config template |
| `cups.uri.example` | Example CUPS URL |

Generated files (not tracked): `station.conf`, `cups.uri`, `cups.key`, `cups.trust`, `tc.*`

## Manual Configuration

If not using `setup-gateway.sh`:

**cups.uri** - CUPS server URL:
```
https://eu1.cloud.thethings.network:443
```

**cups.key** - API key header:
```
Authorization: Bearer NNSXS.YOUR_API_KEY...
```

**cups.trust** - CA certificate:
```bash
curl -o cups.trust https://letsencrypt.org/certs/isrgrootx1.pem
```

## TTN Console

1. Go to [console.cloud.thethings.network](https://console.cloud.thethings.network/)
2. Register gateway with your EUI
3. Create API Key with "Link as Gateway to Gateway Server" permission
