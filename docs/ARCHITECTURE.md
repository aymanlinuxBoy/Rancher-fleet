# Fleet Base Apps - Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Git Repository                         │
│              (GitHub/GitLab/Gitea with Fleet bundles)      │
└────────────────────────────┬────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │ Rancher Fleet   │
                    │ GitOps Engine   │
                    └────────┬────────┘
                             │
                ┌────────────┴─────────────┐
                │                         │
        ┌───────▼────────┐         ┌──────▼──────────┐
        │ UPSTREAM       │         │ DOWNSTREAM     │
        │ (Rancher Host) │         │ (Workload)     │
        └───────┬────────┘         └──────┬──────────┘
                │                        │
        ┌───────▼────────┐         ┌──────▼──────────┐
        │ Base Apps      │         │ Base Apps      │
        │ + Vault        │         │ + ESO          │
        └────────────────┘         └────────────────┘
```

---

## Component Breakdown

### 1. Git Repository Layer

**Role:** Single source of truth for all cluster configuration

**Components:**
- Fleet bundles (one per app)
- `fleet.yaml` files (deployment config)
- `values.yaml` files (Helm chart values)
- Documentation and scripts

**Benefits:**
- Version control for all changes
- Audit trail of deployments
- Easy rollback capability
- Collaboration-friendly (PRs, code review)

---

### 2. Rancher Fleet Layer

**Role:** GitOps reconciliation engine

**How it works:**
1. Watches Git repository for changes
2. Parses Fleet bundles
3. Applies to target clusters (upstream/downstream)
4. Continuously reconciles desired state

**Key Concepts:**

- **Cluster Groups:** Target clusters by label
  - `local` = upstream cluster (Rancher host)
  - `downstream` = workload clusters
  
- **Bundles:** Atomic deployment units
  - Each app = one bundle
  - Contains Helm chart + config
  
- **Rollout Strategies:** Control deployment speed
  - `autoPartitionSize`: deploy to N clusters at once
  - `maxUnavailable`: max pods down during update

---

### 3. Upstream Cluster (Rancher Host)

**Purpose:** Management plane for Rancher and shared services

**Base Apps Deployed:**

```
Upstream Cluster
├── System Apps (Rancher managed)
│   ├── Rancher Management UI
│   ├── Local cluster agent
│   └── Fleet controller
│
├── Infrastructure Layer
│   ├── Cert Manager (required by all)
│   ├── MetalLB (load balancing)
│   ├── Nginx Ingress Controller (ingress)
│   └── Longhorn (distributed storage)
│
├── Observability Layer
│   ├── Prometheus (metrics collection)
│   ├── Grafana (visualization)
│   └── Alert Manager (alerting)
│
├── Logging Layer
│   ├── Fluent Bit (log shipping)
│   └── (Optional: Loki for aggregation)
│
└── Secrets Management Layer
    └── Vault (centralized secrets)
```

**Network Access Pattern:**

```
External Access (HTTPS)
    ↓
MetalLB LoadBalancer (10.x.x.x external IP)
    ↓
Nginx Ingress Controller
    ↓
Applications (internal services)
```

---

### 4. Downstream Cluster (Workload)

**Purpose:** Isolated workload execution

**Base Apps Deployed:**

```
Downstream Cluster
├── Infrastructure Layer
│   ├── Cert Manager (same as upstream)
│   ├── MetalLB (load balancing)
│   ├── Nginx Ingress Controller (ingress)
│   └── Longhorn (distributed storage)
│
├── Observability Layer
│   ├── Prometheus (cluster monitoring)
│   ├── Grafana (visualization)
│   └── (Send metrics to upstream Prometheus?)
│
├── Logging Layer
│   ├── Fluent Bit (log shipping)
│   └── (Optional: send to upstream Loki)
│
└── Secrets Management Layer
    └── External Secrets Operator
        └── (pulls from upstream Vault)
```

---

### 5. Cross-Cluster Secrets Architecture

**Design Pattern: Hub-and-Spoke**

```
                Upstream Cluster
                ┌─────────────────┐
                │  Vault (Hub)    │
                │  - AppRole auth │
                │  - K/V secrets  │
                │  - Policies     │
                └────────┬────────┘
                         │
        ┌────────────────┼────────────────┐
        │ Secrets (HTTPS/TLS)            │
        │ Role ID + Secret ID            │
        │ (Credentials)                  │
        │                                 │
        ▼                                 ▼
    ┌─────────────┐             ┌─────────────┐
    │ Downstream1 │             │ Downstream2 │
    │ ┌─────────┐ │             │ ┌─────────┐ │
    │ │ ESO     │ │             │ │ ESO     │ │
    │ │ClusterS-│ │             │ │ClusterS-│ │
    │ │tore     │ │             │ │tore     │ │
    │ └────┬────┘ │             │ └────┬────┘ │
    │      │      │             │      │      │
    │ ┌────▼──────┐ │           │ ┌────▼──────┐ │
    │ │External   │ │           │ │External   │ │
    │ │Secrets    │ │           │ │Secrets    │ │
    │ │(sync data)│ │           │ │(sync data)│ │
    │ └─────────────┘ │          │ └─────────────┘ │
    └────────────────┘          └────────────────┘
```

**Authentication Flow:**

1. **Setup (once):**
   ```
   Vault (upstream) 
     → Create AppRole
     → Generate Role ID + Secret ID
     → Store in K8s Secret on downstream
   ```

2. **Runtime (continuous):**
   ```
   ExternalSecret (downstream)
     → Read K8s Secret (has credentials)
     → Auth to Vault (AppRole)
     → Fetch secret from path
     → Create/update K8s Secret
     → Repeat on schedule (refreshInterval)
   ```

---

## Data Flow Diagrams

### A. App Deployment Flow

```
User commits to Git
         ↓
Fleet detects change (within seconds)
         ↓
Fleet fetches bundle from repo
         ↓
Fleet applies to cluster(s)
         ↓
Helm installs/updates release
         ↓
Workloads start/restart
         ↓
Service becomes available
```

### B. Secret Sync Flow

```
Admin creates secret in Vault (upstream)
         ↓
ExternalSecret references path (downstream)
         ↓
ESO controller detects ExternalSecret
         ↓
ESO fetches from Vault using AppRole
         ↓
ESO creates K8s Secret
         ↓
App pod mounts Secret as volume/env
         ↓
On refreshInterval, sync repeats
```

### C. Monitoring Flow

```
Prometheus scrapes targets
         ↓
Metrics stored in TSDB
         ↓
Grafana queries Prometheus
         ↓
Dashboards display metrics
         ↓
AlertManager evaluates rules
         ↓
Alerts sent if thresholds exceeded
```

---

## Dependency Graph

```
Order of deployment (dependencies):

1. Cert Manager (required by many)
   ↓
2. MetalLB (needed for LoadBalancer IPs)
   ├─→ Nginx Ingress Controller
   │   └─→ Application Ingresses
   └─→ External Access
   
3. Longhorn (persistent storage)
   ↓
4. Prometheus + Grafana (monitoring)
   └─→ ServiceMonitors (scrape targets)
   
5. Fluent Bit (log shipping)
   └─→ Optional: Loki (log aggregation)
   
6. Vault (secrets - upstream only)
   ↓
7. External Secrets Operator (downstream only)
   └─→ ExternalSecrets (app-level)
```

**Why this order?**

- **Cert Manager first:** Others need TLS certificates
- **MetalLB & Nginx:** Needed for external access
- **Storage early:** Many apps use PVCs
- **Monitoring:** Observes other apps
- **Vault late:** Foundation for it (storage) must be ready
- **ESO after Vault:** Requires Vault to already be running

---

## High Availability Considerations

### Current State (POC)

```
Single instance per component
├── 1 x Vault
├── 1 x Prometheus
├── 1 x Grafana
├── 1 x Nginx Controller
└── Distributed storage (Longhorn) across 3 nodes
```

### Production HA Setup

```
Multiple instances + replication
├── 3 x Vault (HA Raft backend)
├── 2 x Prometheus (with remote storage)
├── 2 x Grafana (with shared dashboards)
├── 3 x Nginx Controller (DaemonSet)
└── Longhorn volume replication: 3 copies
```

**Production Changes:**

```yaml
# Vault: switch from dev to HA
ha:
  enabled: true
  replicas: 3
  raft:
    enabled: true

# Prometheus: add retention
prometheusSpec:
  retention: 30d
  replicas: 2

# Nginx: use DaemonSet
kind: DaemonSet
replicas: 3

# Longhorn: set replica count
persistence:
  defaultClassReplicaCount: 3
```

---

## Scaling Scenarios

### Scenario 1: Add Third Downstream Cluster

```
1. Register new cluster in Rancher
2. Label it: cluster.fleet.cattle.io/name=downstream3
3. Fleet automatically deploys bundles
4. Create new AppRole in Vault for this cluster
5. Deploy External Secrets there too
```

### Scenario 2: Increase App Replicas

```
1. Modify ExternalSecret refreshInterval
2. Or update Pod replicas in deployment
3. Push to Git
4. Fleet reconciles automatically
```

### Scenario 3: Add New Monitoring Target

```
1. Deploy app with ServiceMonitor
2. Prometheus auto-scrapes (no manual config)
3. Metrics appear in Grafana
```

---

## Security Boundaries

```
┌────────────────────────────────────────────┐
│ Rancher Cluster (Upstream)                 │
│                                            │
│ ┌──────────────────────────────────────┐  │
│ │ Vault (isolated namespace)           │  │
│ │ - RBAC restricted                    │  │
│ │ - Encrypted storage                  │  │
│ │ - Audit logging                      │  │
│ └──────────────────────────────────────┘  │
│                                            │
│ ┌──────────────────────────────────────┐  │
│ │ Monitoring (read-only prometheus)    │  │
│ │ - No secret access                   │  │
│ │ - Limited scrape targets             │  │
│ └──────────────────────────────────────┘  │
└────────────────────────────────────────────┘
         ↓ (network call via TLS)
         │ (AppRole credentials only)
         │
┌────────────────────────────────────────────┐
│ Workload Cluster (Downstream)              │
│                                            │
│ ┌──────────────────────────────────────┐  │
│ │ External Secrets Operator            │  │
│ │ - Read Vault via AppRole             │  │
│ │ - Sync to specific paths only        │  │
│ └──────────────────────────────────────┘  │
│                                            │
│ ┌──────────────────────────────────────┐  │
│ │ Applications                          │  │
│ │ - Mount secrets from K8s             │  │
│ │ - No direct Vault access             │  │
│ └──────────────────────────────────────┘  │
└────────────────────────────────────────────┘
```

---

## Network Requirements

### Upstream → Downstream (minimal)

- Fleet syncs from Git (outbound to Git repo)
- Vault exposes service for ESO (port 8200)

### Downstream → Upstream

- External Secrets → Vault (HTTPS 8200)
- (Optional) Prometheus → Upstream Prometheus

### External

- Users → Nginx Ingress → Apps (HTTPS 443, HTTP 80)
- Git CI/CD → Git Repo (HTTPS 443)

---

## Backup & Disaster Recovery

### Critical Data to Backup

```
Upstream:
├── Vault data (encryption keys + secrets)
├── Prometheus DB (historical metrics)
├── Grafana dashboards (JSON)
├── Longhorn snapshots
└── Git history (if self-hosted)

Downstream:
├── Application data (on Longhorn)
└── Configuration (in etcd)
```

### Recovery Process

```
1. Restore Vault from backup
   → Restore encryption keys
   → Restore secret data
   
2. Restore Prometheus DB
   → Restore metrics
   → Re-configure scrapes
   
3. Restore Longhorn volumes
   → Snapshot recovery
   
4. Re-apply Fleet bundles (from Git)
   → Full cluster rebuild
```

