# Rancher Fleet - Base Apps Repository

This repository contains GitOps Fleet bundles for deploying base infrastructure applications across Kubernetes clusters managed by Rancher.

## Repository Structure

```
fleet-base-apps/
├── README.md                          # This file
├── fleet.yaml                         # Root Fleet config
├── .gitignore
├── bundles/                           # Application bundles
│   ├── cert-manager/                  # TLS certificate automation
│   ├── metallb/                       # Bare-metal load balancer
│   ├── nginx-ingress-controller/      # Ingress controller
│   ├── longhorn/                      # Distributed storage
│   ├── prometheus-grafana/            # Monitoring stack
│   ├── fluent-bit/                    # Log shipping
│   ├── vault/                         # Centralized secrets (UPSTREAM only)
│   └── external-secrets-operator/     # Secret sync (DOWNSTREAM only)
├── manifests/
│   ├── clustersecretstore.yaml        # Vault backend configuration
│   └── externalsecret-examples.yaml   # Example secret patterns
├── scripts/
│   ├── vault-setup.sh                 # Vault AppRole automation
│   ├── test-vault-sync.sh             # Test secret sync
│   └── troubleshoot.sh                # Diagnostic helper
└── docs/
    ├── DEPLOYMENT_GUIDE.md            # Step-by-step deployment
    ├── VAULT_SETUP.md                 # Secrets management guide
    ├── TROUBLESHOOTING.md             # Issue resolution
    └── ARCHITECTURE.md                # System design
```

## Quick Start

### Prerequisites
- Upstream cluster (Rancher host) with 3 nodes
- Downstream cluster (workload) with 3 nodes, registered in Rancher
- `kubectl` configured with access to both clusters

### Setup (30 minutes)

1. **Update domain names:**
   ```bash
   sed -i 's/yourdomain.local/your-domain.com/g' bundles/*/fleet.yaml
   sed -i 's/192.168.1.240-192.168.1.250/YOUR_IP_RANGE/g' bundles/metallb/fleet.yaml
   ```

2. **Commit and push:**
   ```bash
   git add .
   git commit -m "Configure for your environment"
   git push origin main
   ```

3. **Add to Rancher Fleet:**
   - Rancher UI → **Continuous Delivery** → **Git Repos** → **Add Repo**
   - Repository URL: `https://github.com/aymanlinuxBoy/Rancher-fleet`
   - Branch: `main`
   - Paths: `bundles/`

4. **Monitor deployment:**
   ```bash
   kubectl -n fleet-default get bundles -w
   ```

## Base Applications

| App | Cluster | Purpose |
|-----|---------|---------|
| **Cert Manager** | All | Automated TLS certificates |
| **MetalLB** | All | Bare-metal load balancing (⚠️ configure IP pool) |
| **Nginx Ingress** | All | HTTP/HTTPS ingress controller |
| **Longhorn** | All | Distributed persistent storage |
| **Prometheus** | All | Metrics collection |
| **Grafana** | All | Metrics visualization (⚠️ change admin password) |
| **Fluent Bit** | All | Log shipping |
| **Vault** | Upstream only | Centralized secrets management |
| **External Secrets** | Downstream only | Secret sync from Vault |

## Key Features

- ✅ **GitOps:** All state defined in Git
- ✅ **Multi-cluster:** Separate configs for upstream and downstream
- ✅ **Automated:** Fleet continuously reconciles desired state
- ✅ **Secure:** Vault for centralized secrets, External Secrets for sync
- ✅ **Observable:** Built-in monitoring with Prometheus + Grafana

## Important Customizations

**Before deployment, edit these files:**

| File | Change |
|------|--------|
| `bundles/metallb/fleet.yaml` | Update MetalLB IP pool for your network |
| `bundles/prometheus-grafana/fleet.yaml` | Change Grafana admin password |
| All `bundles/*/fleet.yaml` | Replace `yourdomain.local` with your domain |

## Monitoring & Access

| App | URL | Cluster |
|-----|-----|---------|
| Prometheus | `https://prometheus.your-domain.com` | Upstream |
| Grafana | `https://grafana.your-domain.com` | Upstream |
| Vault UI | `https://vault.your-domain.com` | Upstream |
| Longhorn | `https://longhorn-ui.your-domain.com` | Upstream |

## Documentation

- **[DEPLOYMENT_GUIDE.md](./docs/DEPLOYMENT_GUIDE.md)** — Complete step-by-step deployment
- **[VAULT_SETUP.md](./docs/VAULT_SETUP.md)** — Cross-cluster secrets with Vault + External Secrets
- **[TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md)** — Common issues & fixes
- **[ARCHITECTURE.md](./docs/ARCHITECTURE.md)** — System design & components

## Deployment Order

1. **Cert Manager** (required by others)
2. **MetalLB** (load balancing)
3. **Nginx Ingress Controller** (ingress)
4. **Longhorn** (storage)
5. **Prometheus + Grafana** (monitoring)
6. **Fluent Bit** (logging)
7. **Vault** (upstream only)
8. **External Secrets Operator** (downstream only)

Fleet handles this automatically, but monitor each bundle's status.

## Vault Setup (Optional)

For cross-cluster secrets management:

```bash
cd scripts
chmod +x vault-setup.sh
./vault-setup.sh

# Follow output instructions
# Apply manifests/clustersecretstore.yaml to downstream cluster
```

See [VAULT_SETUP.md](./docs/VAULT_SETUP.md) for complete guide.

## Troubleshooting

### Bundle stuck in "WaitApplyServer"
See [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) → "Bundle Deployment Issues"

### Pod won't start
See [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) → "Pod Issues"

### Ingress not accessible
See [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) → "Networking & Ingress Issues"

## Quick Diagnostic Check

```bash
# Check bundle status
kubectl -n fleet-default get bundles

# Check pod status in each namespace
kubectl get pods -n cert-manager
kubectl get pods -n metallb-system
kubectl get pods -n ingress-nginx
kubectl get pods -n longhorn-system
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get pods -n vault           # Upstream only
kubectl get pods -n external-secrets-system  # Downstream only

# Check Fleet controller logs
kubectl -n fleet-system logs -l app=fleet-controller --tail=50
```

## Next Steps After Deployment

1. ✅ Deploy all base apps
2. ✅ Verify all apps running
3. → Configure Vault for secrets management (optional)
4. → Deploy your applications
5. → Setup monitoring dashboards
6. → Configure alerting rules
7. → Plan backup & disaster recovery

## Security Notes

⚠️ **DO NOT commit to Git:**
- Vault credentials or tokens
- AppRole IDs/Secrets
- Database passwords
- Private encryption keys

The `.gitignore` file prevents accidental commits of sensitive files.

## Production Recommendations

- Switch Vault from dev mode to HA mode
- Enable proper TLS certificates (Cert Manager handles this)
- Setup backup policies for Vault and Prometheus
- Configure log aggregation (Loki/ELK)
- Setup monitoring dashboards and alerts
- Review and tighten RBAC policies

See [DEPLOYMENT_GUIDE.md](./docs/DEPLOYMENT_GUIDE.md) → "Security Considerations" for details.

## Support

For issues:
1. Check [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md)
2. Review relevant documentation
3. Check application logs: `kubectl logs -n <namespace> -l app=<app-name>`
4. Check Fleet controller: `kubectl -n fleet-system logs -l app=fleet-controller`

## License

This configuration is provided for your Rancher deployment.

## Quick Links

- [Rancher Fleet Docs](https://fleet.rancher.io/)
- [Vault Documentation](https://www.vaultproject.io/docs)
- [External Secrets Docs](https://external-secrets.io/)
- [Longhorn Docs](https://longhorn.io/docs/)
- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Docs](https://grafana.com/docs/)
