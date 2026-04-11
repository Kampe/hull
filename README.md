<div align="center">

<img src=".github/icon.svg" alt="" width="96" height="96">

<h1>Hull</h1>

[![CI](https://github.com/Kampe/hull/actions/workflows/ci.yaml/badge.svg)](https://github.com/Kampe/hull/actions/workflows/ci.yaml)
[![Helm](https://img.shields.io/badge/Helm-1.0.0-blue?logo=helm)](https://github.com/Kampe/hull)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

**A general-purpose Helm chart for deploying applications to Kubernetes.**
**One chart to rule them all.**

</div>

<br>

Hull replaces the need for hundreds of app-specific charts. It's designed for GitOps-managed homelabs and production clusters where you want **convention over configuration** without the footguns.

> **8 lines of YAML** to deploy an app with a Service, Ingress, TLS, DNS, and auto-probes.
> Zero hidden env vars. Zero hidden volume mounts. Zero surprise security contexts.

---

## Philosophy

| | Principle |
|---|---|
| **1** | **Convention over configuration** — sane defaults that work for 90% of apps with zero overrides |
| **2** | **No footguns** — never silently break a deployment with hidden defaults |
| **3** | **Explicit is better than implicit** — if a feature is enabled, the user asked for it |
| **4** | **Multi-container first class** — sidecars are as easy as the main container |
| **5** | **GitOps native** — everything is declarative YAML, no imperative setup steps |

## Quick Start

### Install from OCI Registry

```bash
helm install my-app oci://ghcr.io/kampe/hull --version 1.0.0 -f values.yaml
```

### Minimal Deployment (8 lines)

```yaml
image:
  repository: glanceapp/glance
  tag: latest

service:
  main:
    port: 8080

ingress:
  main:
    hostname: glance.example.com
```

That's it. This gives you:
- A `Deployment` with one container running the image
- A `ClusterIP` Service on port 8080
- An `Ingress` with TLS (via cert-manager) and external-dns
- Auto-generated HTTP probes on port 8080
- No hidden env vars, no hidden volume mounts, no surprise security contexts

## Features

### Containers

Hull supports single containers, sidecars, and init containers — all with the same configuration surface.

**Main container:**

```yaml
image:
  repository: nginx
  tag: latest

ports:
  - name: http
    containerPort: 8080

env:
  APP_ENV: production
  DATABASE_URL:
    secretKeyRef:
      name: app-secrets
      key: database-url
```

**Sidecars** run in the same pod:

```yaml
sidecars:
  redis:
    image:
      repository: redis
      tag: "7"
    port: 6379
  chrome:
    image:
      repository: gcr.io/zenika-hub/alpine-chrome
      tag: "124"
    args: ["--no-sandbox", "--headless", "--remote-debugging-port=9222"]
    port: 9222
    env:
      CHROME_FLAGS: "--disable-gpu"
```

**Init containers:**

```yaml
initContainers:
  migrations:
    image:
      repository: my-app
      tag: latest
    command: ["sh", "-c", "run-migrations"]
    env:
      DATABASE_URL:
        secretKeyRef:
          name: app-secrets
          key: database-url
```

### Smart Probes

Probes are automatically generated based on your ports:

- **HTTP ports** (named `http`, `web`, `main`, or on common ports like 80, 8080, 3000) → `httpGet` probes on `/`
- **Non-HTTP ports** (like redis 6379, mongo 27017) → `tcpSocket` probes
- **Startup probes** get generous defaults: `failureThreshold: 30`, `periodSeconds: 5` (allows 2.5 minutes to start)

**No ports defined?** No probes generated. No errors. No footguns.

**Override or disable:**

```yaml
probes:
  # Disable all probes
  enabled: false

  # Or customize individually
  liveness:
    path: /healthz
    periodSeconds: 15
  readiness:
    type: exec
    command: ["pg_isready"]
  startup:
    enabled: false
```

### Services

Service definitions can infer target ports from your container ports, but you still opt in by defining the service you want to expose:

```yaml
# Minimal: just set the port
service:
  main:
    port: 8080

# Multiple ports on one Service
service:
  main:
    ports:
      http:
        port: 80
        targetPort: http
      grpc:
        port: 9090
        targetPort: grpc

# Expose a sidecar on its own Service
service:
  redis:
    targetContainer: redis
    ports:
      redis:
        port: 6379
        targetPort: redis

# Full options
service:
  main:
    port: 8080
    type: LoadBalancer
    loadBalancerIP: 10.0.0.1
    annotations:
      metallb.universe.tf/address-pool: default
```

### Ingress

Ingress configuration is designed to eliminate boilerplate. All the common patterns are built in as simple toggles.

```yaml
ingress:
  main:
    hostname: app.example.com
    certManager: true        # adds cert-manager.io/cluster-issuer: vault-issuer
    externalDns: true        # adds external-dns annotation
    authentik: true          # adds full Authentik forward-auth annotation block
    proxyBodySize: "0"       # adds nginx proxy-body-size annotation

    # Custom annotations are merged with generated ones
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
```

**Multiple ingresses:**

```yaml
ingress:
  main:
    hostname: app.example.com
  api:
    hostname: api.example.com
    path: /api
    service: main
```

**Custom cluster issuer:**

```yaml
ingress:
  main:
    hostname: app.example.com
    clusterIssuer: vault-issuer  # default: vault-issuer
```

**Disable cert-manager or external-dns:**

```yaml
ingress:
  main:
    hostname: app.example.com
    certManager: false
    externalDns: false
```

### Gateway API (HTTPRoute)

Switch from Ingress to Gateway API with a single flag:

```yaml
routeType: gateway
gatewayName: main-gateway
gatewayNamespace: gateway-system
gatewaySectionName: https

ingress:
  main:
    hostname: app.example.com
```

This generates an `HTTPRoute` instead of an `Ingress`. The `ingress` block syntax is the same — only the rendered resource changes.

Per-route gateway overrides are also supported:

```yaml
ingress:
  main:
    hostname: app.example.com
    gatewayName: internal-gateway
  api:
    hostname: api.example.com
    gatewayName: external-gateway
```

### Persistence

Named volumes with predictable naming (`<release>-<volume-name>`):

```yaml
persistence:
  # PersistentVolumeClaim (default)
  data:
    size: 5Gi
    mountPath: /data
    storageClass: longhorn     # optional
    accessMode: ReadWriteOnce  # default

  # NFS
  media:
    type: nfs
    server: 192.168.1.100
    path: /mnt/media
    mountPath: /media

  # EmptyDir
  cache:
    type: emptyDir
    mountPath: /cache

  # ConfigMap
  config:
    type: configmap
    objectName: app-settings
    mountPath: /etc/app/config.yml
    subPath: config.yml
    items:
      - key: config.yml
        path: config.yml

  # Secret
  certs:
    type: secret
    objectName: vault-ca
    mountPath: /etc/ssl/certs/
    items:
      - key: ca.crt
        path: ca.crt

  # HostPath
  device:
    type: hostPath
    hostPath: /dev/bus/usb
    hostPathType: Directory
    mountPath: /dev/bus/usb

  # StatefulSet volumeClaimTemplate
  db:
    type: volumeClaimTemplate
    size: 20Gi
    mountPath: /var/lib/postgresql/data
```

**Target specific containers:**

```yaml
persistence:
  data:
    size: 5Gi
    mountPath: /data
    # Mounts in all containers (default)

  meili-data:
    size: 2Gi
    mountPath: /meili_data
    containers: [meilisearch]  # Only mount in the meilisearch sidecar
```

### ConfigMaps

```yaml
configMaps:
  app-settings:
    data:
      config.yml: |
        server:
          port: 80
        logging:
          level: info
      simple-key: simple-value
```

ConfigMaps are named `<release>-<name>`. Mount them via the persistence section using `type: configmap`.

### Security Presets

Three presets to avoid security context boilerplate:

| Preset | What it does |
|--------|-------------|
| `default` | No security context at all. Let the image decide. **(This is the default.)** |
| `restricted` | `runAsNonRoot`, `readOnlyRootFilesystem`, `drop ALL` capabilities, `allowPrivilegeEscalation: false` |
| `root` | `runAsUser: 0`, `runAsGroup: 0` |

```yaml
securityPreset: restricted
```

**Override on top of a preset:**

```yaml
securityPreset: restricted
securityContext:
  runAsUser: 1000
```

**Pod-level security:**

```yaml
podSecurityContext:
  fsGroup: 1000
  fsGroupChangePolicy: OnRootMismatch
```

### Metrics / ServiceMonitor

```yaml
metrics:
  enabled: true
  port: http         # port name to scrape
  path: /metrics
  interval: 30s
  labels:
    team: platform
```

Generates a `ServiceMonitor` with `instance: primary` label by default (configurable via `labels`).

### Service Account & RBAC

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::role/my-role

rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["pods"]
      verbs: ["get", "list"]
```

### Network Policy

```yaml
networkPolicy:
  enabled: true
  # Default: allows ingress on service ports, egress to DNS + everywhere
  # Override with custom rules:
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - port: 8080
```

### Workload Types

```yaml
# Default: Deployment
workloadType: Deployment

# StatefulSet (auto-sets serviceName)
workloadType: StatefulSet
```

### Pod Spec

All standard pod spec fields are pass-through:

```yaml
nodeSelector:
  kubernetes.io/arch: amd64

tolerations:
  - key: dedicated
    operator: Equal
    value: apps
    effect: NoSchedule

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: kubernetes.io/hostname

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule

terminationGracePeriodSeconds: 60
hostNetwork: false
dnsPolicy: ClusterFirst
priorityClassName: high-priority
```

## Environment Variables

Three styles, all in the same `env` block:

```yaml
env:
  # Plain value
  APP_ENV: production

  # From Secret
  DATABASE_URL:
    secretKeyRef:
      name: app-secrets
      key: database-url

  # From ConfigMap
  CONFIG_PATH:
    configMapKeyRef:
      name: app-config
      key: config-path

  # From field reference (downward API)
  POD_NAME:
    fieldRef:
      fieldPath: metadata.name

envFrom:
  - configMapRef:
      name: app-config
  - secretRef:
      name: app-secrets
```

## Real-World Examples

### Glance (Dashboard)

```yaml
image:
  repository: glanceapp/glance
  tag: latest

ports:
  - name: http
    containerPort: 8080

service:
  main:
    port: 8080

ingress:
  main:
    hostname: glance.kampe.kluster
    certManager: true
    externalDns: true
```

### Karakeep (Bookmarks) — Multi-Container

```yaml
image:
  repository: ghcr.io/karakeep-app/karakeep
  tag: latest

ports:
  - name: http
    containerPort: 3000

sidecars:
  chrome:
    image:
      repository: gcr.io/zenika-hub/alpine-chrome
      tag: "124"
    args: ["--no-sandbox", "--headless", "--remote-debugging-port=9222"]
    port: 9222
  meilisearch:
    image:
      repository: getmeili/meilisearch
      tag: v1.13
    port: 7700
    env:
      MEILI_NO_ANALYTICS: "true"

env:
  BROWSER_WEB_URL: "http://localhost:9222"
  MEILI_ADDR: "http://localhost:7700"

service:
  main:
    port: 3000

ingress:
  main:
    hostname: bookmarks.kampe.kluster
    certManager: true
    externalDns: true

persistence:
  data:
    size: 5Gi
    mountPath: /data
  meili:
    size: 2Gi
    mountPath: /meili_data
    containers: [meilisearch]

securityPreset: root
```

### Audiobookshelf — NFS + Metrics + Authentik SSO

```yaml
image:
  repository: ghcr.io/advplyr/audiobookshelf
  tag: latest

ports:
  - name: http
    containerPort: 80

service:
  main:
    port: 80

ingress:
  main:
    hostname: audiobookshelf.kampe.kluster
    certManager: true
    externalDns: true
    authentik: true

persistence:
  config:
    size: 5Gi
    mountPath: /config
  media:
    type: nfs
    server: 192.168.1.100
    path: /mnt/media/media
    mountPath: /audiobooks

metrics:
  enabled: true
  path: /metrics
  port: http

securityPreset: root
```

## What This Chart Does NOT Do

This chart is intentionally opinionated about what it **won't** do, based on real-world pain points with other general-purpose charts:

| Anti-Pattern | Hull's Position |
|-------------|----------------|
| Inject hidden env vars (TZ, PUID, PGID, UMASK, S6_READ_ONLY_ROOT) | **Never.** Your env block is the only source of env vars. |
| Set fsGroup by default | **Never.** Specify it yourself or don't. |
| Auto-mount /tmp, /dev/shm, /var/logs, /shared | **Never.** No hidden volume mounts. |
| Require probes on every container | **Never.** No probes if no ports. No errors either. |
| Drop ALL capabilities by default | **Never.** Too many images break. Use `securityPreset: restricted` to opt in. |
| Set readOnlyRootFilesystem by default | **Never.** Use `securityPreset: restricted` to opt in. |
| Inject Traefik middleware | **Never.** This chart is ingress-controller-agnostic. |
| Require disabling features you don't use | **Never.** No `integrations.traefik.enabled: false` boilerplate. |

## Chart Structure

```
chart/
├── Chart.yaml
├── values.yaml              # Full documented defaults
├── values.schema.json       # JSON Schema for validation
├── templates/
│   ├── _helpers.tpl          # Template helpers
│   ├── deployment.yaml       # Deployment or StatefulSet
│   ├── service.yaml          # One per service definition
│   ├── ingress.yaml          # Ingress resources
│   ├── httproute.yaml        # Gateway API HTTPRoutes
│   ├── configmap.yaml        # User-defined ConfigMaps
│   ├── pvc.yaml              # PersistentVolumeClaims
│   ├── servicemonitor.yaml   # Prometheus ServiceMonitor
│   ├── serviceaccount.yaml   # Optional ServiceAccount
│   ├── rbac.yaml             # Optional ClusterRole/Binding
│   └── networkpolicy.yaml    # Optional NetworkPolicy
└── ci/                       # CI test values
    ├── minimal-values.yaml
    ├── single-container-values.yaml
    ├── multi-container-values.yaml
    ├── ingress-values.yaml
    ├── persistence-values.yaml
    ├── metrics-values.yaml
    ├── security-values.yaml
    ├── gateway-values.yaml
    └── full-values.yaml
```

## Testing

Run the test suite locally:

```bash
# Requires: helm
./tests/test_chart.sh
```

The test suite validates:
- Minimal values (image only — no footguns)
- Single container with ports, service, and ingress
- Multi-container with sidecars
- All Authentik annotation presets
- Every persistence type (PVC, NFS, emptyDir, configmap, secret, hostPath)
- ServiceMonitor generation
- All security presets
- Gateway API HTTPRoute generation
- Full-featured deployment with everything enabled
- Anti-pattern tests (nothing injected that wasn't asked for)
- All CI values files template cleanly
- Edge cases (probes disabled, StatefulSet)

## Using with ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  source:
    chart: hull
    repoURL: ghcr.io/kampe
    targetRevision: 1.0.0
    helm:
      valuesObject:
        image:
          repository: my-app
          tag: latest
        service:
          main:
            port: 8080
        ingress:
          main:
            hostname: my-app.example.com
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
```

## Using with Renovate

Hull is published as an OCI artifact, so Renovate can auto-detect and update it. Add to your `renovate.json`:

```json
{
  "helm-values": {
    "fileMatch": ["values\\.yaml$"]
  }
}
```

## Contributing

1. Fork the repo
2. Create a feature branch
3. Add/modify templates
4. Add test cases to `tests/test_chart.sh` and CI values to `chart/ci/`
5. Run `./tests/test_chart.sh` and confirm all tests pass
6. Open a PR

## License

MIT
