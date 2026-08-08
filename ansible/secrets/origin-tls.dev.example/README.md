# Origin TLS files (example layout)

Copy this directory to `origin-tls.<env>/` (gitignored) and place:

- `tls.crt` — Cloudflare Origin CA certificate (PEM), preferably `*.campaignhub.best`
- `tls.key` — matching private key (PEM)

```bash
cp -R ansible/secrets/origin-tls.dev.example ansible/secrets/origin-tls.dev
# replace placeholders with real Origin CA materials
./ansible/scripts/configure-origin-tls.sh dev
```

Do not commit real certificates or keys.
