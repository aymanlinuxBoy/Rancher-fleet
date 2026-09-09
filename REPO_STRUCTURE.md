# Repository Structure & File Manifest

## Complete Directory Tree

```
.
├── README.md                          # Main repository documentation
├── fleet.yaml                         # Root Fleet GitRepo configuration
├── .gitignore                         # Git ignore file (secrets, credentials)
│
├── bundles/                           # All deployment bundles
│   ├── cert-manager/
│   │   └── fleet.yaml                 # Cert Manager Helm config
│   ├── metallb/
│   │   └── fleet.yaml                 # MetalLB Helm config
│   ├── nginx-ingress-controller/
│   │   └── fleet.yaml                 # Nginx Helm config
│   ├── longhorn/
│   │   └── fleet.yaml                 # Longhorn Helm config
│   ├── prometheus-grafana/
│   │   └── fleet.yaml                 # kube-prometheus-stack Helm config
│   ├── fluent-bit/
│   │   └── fleet.yaml                 # Fluent Bit Helm config
│   ├── vault/
│   │   └── fleet.yaml                 # Vault Helm config (upstream only)
│   └── external-secrets-operator/
│       └── fleet.yaml                 # External Secrets Operator (downstream only)
│
├── manifests/                         # Kubernetes manifests (apply manually)
│   ├── clustersecretstore.yaml        # Vault backend config for ESO
│   └── externalsecret-examples.yaml   # Example ExternalSecret resources
│
├── scripts/                           # Automation scripts
│   ├── vault-setup.sh                 # Setup Vault AppRole authentication
│   ├── test-vault-sync.sh             # Test secret sync between clusters
│   └── troubleshoot.sh                # Diagnostic helper
│
└── docs/                              # Comprehensive documentation
    ├── DEPLOYMENT_GUIDE.md            # Step-by-step deployment
    ├── VAULT_SETUP.md                 # Vault & secrets guide
    ├── TROUBLESHOOTING.md             # Issue resolution
    └── ARCHITECTURE.md                # System design
```

## File Purposes

### Root Level Files

| File | Purpose |
|------|---------|
| `README.md` | Quick start guide and repository overview |
| `fleet.yaml` | Fleet GitRepo config - update `repo:` field with your GitHub URL |
| `.gitignore` | Prevents secrets/credentials from being committed |

### Bundles Directory (`bundles/`)

Each subdirectory contains a single application bundle:

| Bundle | Deploys To | Key Config |
|--------|-----------|-----------|
| `cert-manager/fleet.yaml` | All clusters | installCRDs: true |
| `metallb/fleet.yaml` | All clusters | ⚠️ Update IP pool range |
| `nginx-ingress-controller/fleet.yaml` | All clusters | Type: LoadBalancer |
| `longhorn/fleet.yaml` | All clusters | Storage class: longhorn |
| `prometheus-grafana/fleet.yaml` | All clusters | ⚠️ Change admin password |
| `fluent-bit/fleet.yaml` | All clusters | Output destination |
| `vault/fleet.yaml` | Upstream only | Dev mode, ingress domain |
| `external-secrets-operator/fleet.yaml` | Downstream only | Webhook cert setup |

### Manifests Directory (`manifests/`)

| File | Purpose | When Apply |
|------|---------|-----------|
| `clustersecretstore.yaml` | Vault backend config for External Secrets | After vault-setup.sh |
| `externalsecret-examples.yaml` | 5 example patterns for syncing secrets | Reference, customize for your apps |

### Scripts Directory (`scripts/`)

| Script | Purpose | When Run |
|--------|---------|----------|
| `vault-setup.sh` | Setup Vault AppRole authentication | Once, after Vault deployed |
| `test-vault-sync.sh` | Verify External Secrets sync works | After ESO deployed |
| `troubleshoot.sh` | Gather diagnostics and logs | When debugging issues |

### Docs Directory (`docs/`)

| Document | Length | Purpose | Audience |
|----------|--------|---------|----------|
| `DEPLOYMENT_GUIDE.md` | ~200 lines | Step-by-step setup | DevOps engineers |
| `VAULT_SETUP.md` | ~300 lines | Secrets architecture | Security engineers |
| `TROUBLESHOOTING.md` | ~300 lines | Issue resolution | Operators |
| `ARCHITECTURE.md` | ~400 lines | System design | Technical leads |

## Quick Reference

### Customization Checklist

Before first deployment:
- [ ] `bundles/metallb/fleet.yaml` → Update IP pool for your network
- [ ] `bundles/prometheus-grafana/fleet.yaml` → Change Grafana admin password
- [ ] All `bundles/*/fleet.yaml` → Replace `yourdomain.local` with your domain
- [ ] `fleet.yaml` → Update `repo:` to your GitHub URL

### Essential Reading Order

1. **First time setup:** README.md → docs/DEPLOYMENT_GUIDE.md
2. **For Vault/Secrets:** docs/VAULT_SETUP.md
3. **For troubleshooting:** docs/TROUBLESHOOTING.md
4. **For understanding design:** docs/ARCHITECTURE.md

### Deploy Order

Fleet handles dependency management, but bundles deploy in order:
1. Cert Manager (required by many)
2. MetalLB
3. Nginx Ingress Controller
4. Longhorn
5. Prometheus + Grafana
6. Fluent Bit
7. Vault (upstream only)
8. External Secrets Operator (downstream only)

### Common Tasks

| Task | File | Command |
|------|------|---------|
| Add to Rancher Fleet | `fleet.yaml` | Edit `repo:` field and push to GitHub |
| Configure monitoring | `bundles/prometheus-grafana/fleet.yaml` | Update ingress domain, admin password |
| Setup secrets management | `scripts/vault-setup.sh` | Run script, apply manifests |
| Troubleshoot issues | `docs/TROUBLESHOOTING.md` | Reference appropriate section |
| Add new application | `bundles/new-app/fleet.yaml` | Create new bundle directory |

## Security Notes

### Files to Never Commit

- Vault credentials/tokens
- AppRole IDs and Secrets
- Database passwords
- Private SSH keys
- API keys

All these are protected by `.gitignore`.

### Safe to Commit

- Helm chart configurations
- Bundle definitions (`fleet.yaml`)
- Documentation
- Scripts (no secrets embedded)

## Version Control Workflow

```bash
# Make changes
vim bundles/some-app/fleet.yaml

# Commit
git add .
git commit -m "Update some-app configuration"

# Push (Fleet auto-reconciles)
git push origin main

# Monitor
kubectl -n fleet-default get bundle some-app -w
```

## Git Configuration

```bash
# Clone your forked repo
git clone https://github.com/aymanlinuxBoy/Rancher-fleet.git
cd Rancher-fleet

# Make changes and commit
git add .
git commit -m "Your message"

# Push to GitHub
git push origin main

# Fleet detects changes within seconds
```

## Next Steps

1. Update customizations (see Customization Checklist)
2. Commit and push to GitHub
3. Add to Rancher Fleet UI
4. Monitor deployment with: `kubectl -n fleet-default get bundles -w`
5. Follow DEPLOYMENT_GUIDE.md for verification steps
