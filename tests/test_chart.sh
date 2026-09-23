#!/usr/bin/env bash
# Hull Helm Chart Test Suite
# Run: ./tests/test_chart.sh
# Requires: helm, yq (or python3 -c 'import yaml')

set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)/chart"
PASS=0
FAIL=0
ERRORS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert() {
  local description="$1"
  local condition="$2"

  if eval "$condition"; then
    PASS=$((PASS + 1))
    printf "${GREEN}  ✓${NC} %s\n" "$description"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$description")
    printf "${RED}  ✗${NC} %s\n" "$description"
  fi
}

assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"

  if echo "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
    printf "${GREEN}  ✓${NC} %s\n" "$description"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$description (expected to find: $needle)")
    printf "${RED}  ✗${NC} %s\n" "$description"
  fi
}

assert_not_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"

  if ! echo "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
    printf "${GREEN}  ✓${NC} %s\n" "$description"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$description (should NOT contain: $needle)")
    printf "${RED}  ✗${NC} %s\n" "$description"
  fi
}

render() {
  helm template test "$CHART_DIR" "$@" 2>&1
}

assert_renders() {
  local description="$1"
  local values_file="$2"
  local result

  if helm template test "$CHART_DIR" -f "$values_file" >/dev/null 2>&1; then
    result="ok"
  else
    result="fail"
  fi

  assert "$description" "[[ '$result' == 'ok' ]]"
}

# ============================================================================
printf "${YELLOW}━━━ Minimal Values ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render --set image.repository=nginx --set image.tag=latest)

assert "Minimal: templates successfully" \
  "[[ $? -eq 0 ]]"

assert_contains "Minimal: generates Deployment" \
  "$OUTPUT" "kind: Deployment"

assert_not_contains "Minimal: no implicit Service without ports or service config" \
  "$OUTPUT" "kind: Service"

assert_contains "Minimal: image is nginx:latest" \
  "$OUTPUT" "image: nginx:latest"

assert_not_contains "Minimal: no Ingress generated" \
  "$OUTPUT" "kind: Ingress"

assert_not_contains "Minimal: no PVC generated" \
  "$OUTPUT" "kind: PersistentVolumeClaim"

assert_not_contains "Minimal: no ServiceMonitor generated" \
  "$OUTPUT" "kind: ServiceMonitor"

assert_not_contains "Minimal: no NetworkPolicy generated" \
  "$OUTPUT" "kind: NetworkPolicy"

assert_not_contains "Minimal: no ServiceAccount generated" \
  "$OUTPUT" "kind: ServiceAccount"

assert_not_contains "Minimal: no securityContext on container" \
  "$OUTPUT" "securityContext:"

assert_not_contains "Minimal: no probes (no ports defined)" \
  "$OUTPUT" "livenessProbe:"

assert_not_contains "Minimal: no env vars injected" \
  "$OUTPUT" "env:"

assert_not_contains "Minimal: no volumeMounts" \
  "$OUTPUT" "volumeMounts:"

assert_not_contains "Minimal: no hidden /tmp mount" \
  "$OUTPUT" "/tmp"

assert_not_contains "Minimal: no hidden /dev/shm mount" \
  "$OUTPUT" "/dev/shm"

assert_not_contains "Minimal: no TZ env var" \
  "$OUTPUT" "name: \"TZ\""

assert_not_contains "Minimal: no PUID env var" \
  "$OUTPUT" "name: \"PUID\""

assert_not_contains "Minimal: no UMASK env var" \
  "$OUTPUT" "name: \"UMASK\""

assert_not_contains "Minimal: no fsGroup set" \
  "$OUTPUT" "fsGroup:"

# ============================================================================
printf "\n${YELLOW}━━━ Single Container with Ports ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/single-container-values.yaml")

assert_contains "Single: auto-generates httpGet liveness probe" \
  "$OUTPUT" "httpGet:"

assert_contains "Single: probe targets port http" \
  "$OUTPUT" "port: http"

assert_contains "Single: startup probe has failureThreshold 30" \
  "$OUTPUT" "failureThreshold: 30"

assert_contains "Single: service port is 8080" \
  "$OUTPUT" "port: 8080"

assert_contains "Single: generates Ingress" \
  "$OUTPUT" "kind: Ingress"

assert_contains "Single: ingress hostname is glance.example.com" \
  "$OUTPUT" "host: glance.example.com"

assert_contains "Single: cert-manager annotation present" \
  "$OUTPUT" "cert-manager.io/cluster-issuer: vault-issuer"

assert_contains "Single: external-dns annotation present" \
  "$OUTPUT" "external-dns.alpha.kubernetes.io/hostname"

assert_contains "Single: TLS secret generated" \
  "$OUTPUT" "secretName: test-hull-tls"

assert_contains "Single: ingressClassName is nginx" \
  "$OUTPUT" "ingressClassName: nginx"

# ============================================================================
printf "\n${YELLOW}━━━ Multi-Container (Sidecars) ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/multi-container-values.yaml")

assert_contains "Multi: main container present" \
  "$OUTPUT" "name: main"

assert_contains "Multi: chrome sidecar present" \
  "$OUTPUT" "name: chrome"

assert_contains "Multi: meilisearch sidecar present" \
  "$OUTPUT" "name: meilisearch"

assert_contains "Multi: chrome image correct" \
  "$OUTPUT" "image: gcr.io/zenika-hub/alpine-chrome:124"

assert_contains "Multi: meilisearch image correct" \
  "$OUTPUT" "image: getmeili/meilisearch:v1.13"

assert_contains "Multi: chrome gets TCP probe (non-http port)" \
  "$OUTPUT" "tcpSocket:"

assert_contains "Multi: chrome port 9222" \
  "$OUTPUT" "containerPort: 9222"

assert_contains "Multi: meilisearch port 7700" \
  "$OUTPUT" "containerPort: 7700"

assert_contains "Multi: meilisearch env var set" \
  "$OUTPUT" 'MEILI_NO_ANALYTICS'

assert_contains "Multi: data PVC created" \
  "$OUTPUT" "name: test-hull-data"

assert_contains "Multi: meili PVC created" \
  "$OUTPUT" "name: test-hull-meili"

assert_contains "Multi: root security preset applied" \
  "$OUTPUT" "runAsUser: 0"

# Check that meili volume is only mounted in meilisearch container
# (and main, since data has no containers restriction)
assert_contains "Multi: meili mountPath present" \
  "$OUTPUT" "mountPath: /meili_data"

# ============================================================================
printf "\n${YELLOW}━━━ EnvFrom Support ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/envfrom-values.yaml")

assert_contains "EnvFrom: main container envFrom rendered" \
  "$OUTPUT" "envFrom:"

assert_contains "EnvFrom: generated ConfigMap ref expanded to fullname" \
  "$OUTPUT" 'name: "test-hull-app-env"'

assert_contains "EnvFrom: secretRef preserved" \
  "$OUTPUT" 'name: "app-secrets"'

assert_contains "EnvFrom: sidecar envFrom rendered" \
  "$OUTPUT" 'name: "worker-secrets"'

assert_contains "EnvFrom: init container envFrom rendered" \
  "$OUTPUT" "name: setup"

# ============================================================================
printf "\n${YELLOW}━━━ Advanced Services ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/advanced-services-values.yaml")

assert_contains "Services: main service exposes http port 80" \
  "$OUTPUT" "port: 80"

assert_contains "Services: main service targets named http port" \
  "$OUTPUT" "targetPort: http"

assert_contains "Services: main service exposes grpc port" \
  "$OUTPUT" "targetPort: grpc"

assert_contains "Services: sidecar service rendered" \
  "$OUTPUT" "name: test-hull-redis"

assert_contains "Services: sidecar service exposes redis port" \
  "$OUTPUT" "targetPort: redis"

assert_contains "Services: sidecar service exposes metrics port" \
  "$OUTPUT" "targetPort: metrics"

assert_not_contains "Services: disabled sidecar probes are omitted" \
  "$OUTPUT" "livenessProbe:"

# ============================================================================
printf "\n${YELLOW}━━━ Ingress with Authentik ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/ingress-values.yaml")

assert_contains "Authentik: auth-url annotation" \
  "$OUTPUT" "nginx.ingress.kubernetes.io/auth-url"

assert_contains "Authentik: auth-signin with correct hostname" \
  "$OUTPUT" "audiobookshelf.example.com/outpost.goauthentik.io/start"

assert_contains "Authentik: auth-response-headers" \
  "$OUTPUT" "X-authentik-username"

assert_contains "Authentik: server-snippet with outpost proxy" \
  "$OUTPUT" "ak-outpost-authentik-embedded-outpost"

assert_contains "Authentik: proxy-body-size annotation" \
  "$OUTPUT" 'proxy-body-size: "0"'

assert_contains "Authentik: custom annotation merged" \
  "$OUTPUT" "proxy-read-timeout"

# ============================================================================
printf "\n${YELLOW}━━━ Ingress Without Generated Integrations ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/ingress-disabled-integrations-values.yaml")

assert_not_contains "Ingress: no cert-manager annotation when disabled" \
  "$OUTPUT" "cert-manager.io/cluster-issuer"

assert_not_contains "Ingress: no external-dns annotation when disabled" \
  "$OUTPUT" "external-dns.alpha.kubernetes.io/hostname"

# ============================================================================
printf "\n${YELLOW}━━━ Persistence Types ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/persistence-values.yaml")

assert_contains "Persist: PVC for config" \
  "$OUTPUT" "name: test-hull-config"

assert_contains "Persist: PVC size 5Gi" \
  "$OUTPUT" "storage: 5Gi"

assert_contains "Persist: NFS volume" \
  "$OUTPUT" "server: 192.168.1.100"

assert_contains "Persist: NFS path" \
  "$OUTPUT" "path: /mnt/media/media"

assert_contains "Persist: emptyDir volume" \
  "$OUTPUT" "emptyDir:"

assert_contains "Persist: configMap volume" \
  "$OUTPUT" "name: test-hull-app-settings"

assert_contains "Persist: secret volume" \
  "$OUTPUT" "secretName: vault-ca"

assert_contains "Persist: hostPath volume" \
  "$OUTPUT" "path: /dev/bus/usb"

assert_contains "Persist: configmap data rendered" \
  "$OUTPUT" "config.yml:"

assert_contains "Persist: subPath on configmap mount" \
  "$OUTPUT" "subPath: config.yml"

# ============================================================================
printf "\n${YELLOW}━━━ Metrics / ServiceMonitor ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/metrics-values.yaml")

assert_contains "Metrics: ServiceMonitor generated" \
  "$OUTPUT" "kind: ServiceMonitor"

assert_contains "Metrics: path is /metrics" \
  "$OUTPUT" "path: /metrics"

assert_contains "Metrics: interval is 30s" \
  "$OUTPUT" "interval: 30s"

assert_contains "Metrics: instance: primary label" \
  "$OUTPUT" "instance: primary"

assert_contains "Metrics: custom label merged" \
  "$OUTPUT" "team: platform"

# ============================================================================
printf "\n${YELLOW}━━━ Pod Disruption Budget ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/pdb-values.yaml")

assert_contains "PDB: resource generated" \
  "$OUTPUT" "kind: PodDisruptionBudget"

assert_contains "PDB: minAvailable rendered" \
  "$OUTPUT" "minAvailable: 1"

assert_contains "PDB: custom annotation rendered" \
  "$OUTPUT" "test.example.com/enabled: \"true\""

# ============================================================================
printf "\n${YELLOW}━━━ Security Presets ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/security-values.yaml")

assert_contains "Security: restricted preset drops ALL caps" \
  "$OUTPUT" "- ALL"

assert_contains "Security: restricted preset sets readOnlyRootFilesystem" \
  "$OUTPUT" "readOnlyRootFilesystem: true"

assert_contains "Security: restricted preset sets runAsNonRoot" \
  "$OUTPUT" "runAsNonRoot: true"

assert_contains "Security: pod fsGroup set" \
  "$OUTPUT" "fsGroup: 1000"

assert_contains "Security: fsGroupChangePolicy set" \
  "$OUTPUT" "fsGroupChangePolicy: OnRootMismatch"

assert_contains "Security: ServiceAccount created" \
  "$OUTPUT" "kind: ServiceAccount"

assert_contains "Security: ClusterRole created" \
  "$OUTPUT" "kind: ClusterRole"

assert_contains "Security: ClusterRoleBinding created" \
  "$OUTPUT" "kind: ClusterRoleBinding"

assert_contains "Security: SA annotation present" \
  "$OUTPUT" "eks.amazonaws.com/role-arn"

assert_contains "Security: NetworkPolicy created" \
  "$OUTPUT" "kind: NetworkPolicy"

assert_contains "Security: NetworkPolicy allows port 8080" \
  "$OUTPUT" "port: 8080"

assert_contains "Security: NetworkPolicy allows DNS egress" \
  "$OUTPUT" "port: 53"

# ============================================================================
printf "\n${YELLOW}━━━ Gateway API ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/gateway-values.yaml")

assert_contains "Gateway: HTTPRoute generated" \
  "$OUTPUT" "kind: HTTPRoute"

assert_contains "Gateway: parentRef name" \
  "$OUTPUT" "name: main-gateway"

assert_contains "Gateway: parentRef namespace" \
  "$OUTPUT" "namespace: gateway-system"

assert_contains "Gateway: sectionName https" \
  "$OUTPUT" "sectionName: https"

assert_contains "Gateway: hostname set" \
  "$OUTPUT" "app.example.com"

assert_contains "Gateway: backendRef port" \
  "$OUTPUT" "port: 8080"

assert_not_contains "Gateway: no Ingress generated" \
  "$OUTPUT" "kind: Ingress"

# ============================================================================
printf "\n${YELLOW}━━━ StatefulSet VolumeClaimTemplates ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/statefulset-vct-values.yaml")

assert_contains "StatefulSet: volumeClaimTemplates rendered" \
  "$OUTPUT" "volumeClaimTemplates:"

assert_contains "StatefulSet: data claim template name rendered" \
  "$OUTPUT" "name: data"

assert_contains "StatefulSet: volume claim template storageClass rendered" \
  "$OUTPUT" "storageClassName: fast-ssd"

assert_contains "StatefulSet: volume claim template labels rendered" \
  "$OUTPUT" "backup: daily"

assert_not_contains "StatefulSet: no standalone PVC rendered for volumeClaimTemplate" \
  "$OUTPUT" "kind: PersistentVolumeClaim"

# ============================================================================
printf "\n${YELLOW}━━━ Full Values ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render -f "$CHART_DIR/ci/full-values.yaml")

assert_contains "Full: replicas set to 2" \
  "$OUTPUT" "replicas: 2"

assert_contains "Full: command override" \
  "$OUTPUT" "/bin/sh"

assert_contains "Full: args override" \
  "$OUTPUT" "start-app"

assert_contains "Full: secretKeyRef env" \
  "$OUTPUT" "secretKeyRef:"

assert_contains "Full: configMapKeyRef env" \
  "$OUTPUT" "configMapKeyRef:"

assert_contains "Full: fieldRef env" \
  "$OUTPUT" "fieldRef:"

assert_contains "Full: custom probe path /healthz" \
  "$OUTPUT" "path: /healthz"

assert_contains "Full: custom probe path /readyz" \
  "$OUTPUT" "path: /readyz"

assert_contains "Full: resources requests" \
  "$OUTPUT" "cpu: 200m"

assert_contains "Full: resources limits" \
  "$OUTPUT" "memory: 512Mi"

assert_contains "Full: redis sidecar" \
  "$OUTPUT" "name: redis"

assert_contains "Full: exporter sidecar" \
  "$OUTPUT" "name: exporter"

assert_contains "Full: init container migrations" \
  "$OUTPUT" "name: migrations"

assert_contains "Full: two ingresses generated" \
  "$OUTPUT" "name: test-hull-api"

assert_contains "Full: NFS persistence" \
  "$OUTPUT" "server: 192.168.1.100"

assert_contains "Full: storageClass on PVC" \
  "$OUTPUT" "storageClassName: longhorn"

assert_contains "Full: ServiceMonitor with custom interval" \
  "$OUTPUT" "interval: 15s"

assert_contains "Full: nodeSelector" \
  "$OUTPUT" "kubernetes.io/arch: amd64"

assert_contains "Full: tolerations" \
  "$OUTPUT" "key: dedicated"

assert_contains "Full: affinity" \
  "$OUTPUT" "podAntiAffinity"

assert_contains "Full: topologySpreadConstraints" \
  "$OUTPUT" "maxSkew: 1"

assert_contains "Full: terminationGracePeriodSeconds 60" \
  "$OUTPUT" "terminationGracePeriodSeconds: 60"

assert_contains "Full: podAnnotations" \
  "$OUTPUT" 'prometheus.io/scrape: "true"'

assert_contains "Full: podLabels" \
  "$OUTPUT" "team: platform"

assert_contains "Full: RBAC rules" \
  "$OUTPUT" "kind: ClusterRole"

assert_contains "Full: NetworkPolicy" \
  "$OUTPUT" "kind: NetworkPolicy"

assert_contains "Full: topologySpreadConstraints uses valid whenUnsatisfiable field" \
  "$OUTPUT" "whenUnsatisfiable: DoNotSchedule"

# ============================================================================
printf "\n${YELLOW}━━━ Anti-Pattern Tests (Must NOT Exist) ━━━${NC}\n"
# ============================================================================

OUTPUT=$(render --set image.repository=nginx --set image.tag=latest)

assert_not_contains "Anti: no traefik references" \
  "$OUTPUT" "traefik"

assert_not_contains "Anti: no fixedEnv" \
  "$OUTPUT" "fixedEnv"

assert_not_contains "Anti: no NVIDIA_VISIBLE_DEVICES" \
  "$OUTPUT" "NVIDIA_VISIBLE_DEVICES"

assert_not_contains "Anti: no S6_READ_ONLY_ROOT" \
  "$OUTPUT" "S6_READ_ONLY_ROOT"

assert_not_contains "Anti: no seccomp profile" \
  "$OUTPUT" "seccompProfile"

assert_not_contains "Anti: no readOnlyRootFilesystem by default" \
  "$OUTPUT" "readOnlyRootFilesystem"

assert_not_contains "Anti: no capabilities drop by default" \
  "$OUTPUT" "capabilities"

# ============================================================================
printf "\n${YELLOW}━━━ CI Values Matrix ━━━${NC}\n"
# ============================================================================

for f in "$CHART_DIR"/ci/*.yaml; do
  name=$(basename "$f")
  assert_renders "CI values: $name templates cleanly" "$f"
done

# ============================================================================
printf "\n${YELLOW}━━━ Edge Cases ━━━${NC}\n"
# ============================================================================

# Probes disabled
OUTPUT=$(render --set image.repository=nginx --set image.tag=latest --set probes.enabled=false \
  --set 'ports[0].name=http' --set 'ports[0].containerPort=80')

assert_not_contains "Edge: probes disabled globally" \
  "$OUTPUT" "livenessProbe:"

# StatefulSet workload
OUTPUT=$(render --set image.repository=nginx --set image.tag=latest --set workloadType=StatefulSet)

assert_contains "Edge: StatefulSet generated" \
  "$OUTPUT" "kind: StatefulSet"

assert_contains "Edge: StatefulSet has serviceName" \
  "$OUTPUT" "serviceName:"

# Empty sidecars / persistence maps
OUTPUT=$(render --set image.repository=nginx --set image.tag=latest --set-json sidecars='{}' --set-json persistence='{}')

assert_not_contains "Edge: empty sidecars map does not render sidecar containers" \
  "$OUTPUT" "name: redis"

assert_not_contains "Edge: empty persistence map does not render volumes" \
  "$OUTPUT" "volumes:"

# Schema catches nested invalid env values
SCHEMA_DIR=$(mktemp -d /tmp/hull-schema-nested.XXXXXX)
cat > "$SCHEMA_DIR/bad-sidecar-env.yaml" <<'EOF'
image:
  repository: nginx
  tag: latest
sidecars:
  redis:
    image:
      repository: redis
      tag: "7"
    env:
      BROKEN:
        nope: true
EOF

if helm lint chart/ -f "$SCHEMA_DIR/bad-sidecar-env.yaml" >/dev/null 2>&1; then
  SCHEMA_RESULT="ok"
else
  SCHEMA_RESULT="fail"
fi

assert "Schema: rejects invalid sidecar env shape" \
  "[[ '$SCHEMA_RESULT' == 'fail' ]]"

# Schema catches invalid topology spread fields used in docs/examples
SCHEMA_DIR=$(mktemp -d /tmp/hull-schema-topology.XXXXXX)
cat > "$SCHEMA_DIR/bad-topology.yaml" <<'EOF'
image:
  repository: nginx
  tag: latest
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfied: DoNotSchedule
EOF

if helm lint chart/ -f "$SCHEMA_DIR/bad-topology.yaml" >/dev/null 2>&1; then
  SCHEMA_TOPOLOGY_RESULT="ok"
else
  SCHEMA_TOPOLOGY_RESULT="fail"
fi

assert "Schema: rejects invalid topology spread field names" \
  "[[ '$SCHEMA_TOPOLOGY_RESULT' == 'fail' ]]"

# Schema allows named ports for ingress and integer ports for metrics
SCHEMA_DIR_VALID=$(mktemp -d /tmp/hull-schema-valid.XXXXXX)
cat > "$SCHEMA_DIR_VALID/valid-types.yaml" <<'EOF'
image:
  repository: nginx
  tag: latest
ingress:
  main:
    hostname: test.example.com
    servicePort: http
metrics:
  enabled: true
  port: 8080
EOF

if helm lint chart/ -f "$SCHEMA_DIR_VALID/valid-types.yaml" >/dev/null 2>&1; then
  SCHEMA_TYPES_RESULT="ok"
else
  SCHEMA_TYPES_RESULT="fail"
fi

assert "Schema: accepts named ingress ports and integer metrics ports" \
  "[[ '$SCHEMA_TYPES_RESULT' == 'ok' ]]"

# ============================================================================
# hostPort
# ============================================================================
printf "\n${YELLOW}hostPort${NC}\n"

HOSTPORT_DIR=$(mktemp -d /tmp/hull-hostport.XXXXXX)
cat > "$HOSTPORT_DIR/hostport.yaml" <<EOF
image:
  repository: nginx
  tag: "1.0"
ports:
  - name: http
    containerPort: 32400
    hostPort: 32400
EOF
cat > "$HOSTPORT_DIR/nohostport.yaml" <<EOF
image:
  repository: nginx
  tag: "1.0"
ports:
  - name: http
    containerPort: 8080
EOF

HOSTPORT_OUT="$(render -f "$HOSTPORT_DIR/hostport.yaml")"
NOHOSTPORT_OUT="$(render -f "$HOSTPORT_DIR/nohostport.yaml")"

assert "hostPort: renders on the main container when set" \
  "grep -q 'hostPort: 32400' <<< \"\$HOSTPORT_OUT\""

assert "hostPort: omitted entirely when not set" \
  "! grep -q 'hostPort' <<< \"\$NOHOSTPORT_OUT\""

# ============================================================================
# Summary
# ============================================================================
printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"

if [[ $FAIL -gt 0 ]]; then
  printf "\n${RED}Failed tests:${NC}\n"
  for err in "${ERRORS[@]}"; do
    printf "  - %s\n" "$err"
  done
  exit 1
fi

printf "${GREEN}All tests passed!${NC}\n"
