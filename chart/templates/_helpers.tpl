{{/*
Hull - General purpose Helm chart template helpers
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "hull.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "hull.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart label value.
*/}}
{{- define "hull.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "hull.labels" -}}
helm.sh/chart: {{ include "hull.chart" . }}
{{ include "hull.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "hull.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hull.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "hull.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hull.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolve the image string for a container.
Accepts a dict with "repository" and "tag" keys.
*/}}
{{- define "hull.image" -}}
{{- if .tag }}
{{- printf "%s:%s" .repository (.tag | toString) }}
{{- else }}
{{- .repository }}
{{- end }}
{{- end }}

{{/*
Resolve a ConfigMap name. Generated ConfigMaps are referenced by their short
key in values, but rendered as <release>-<name>.
*/}}
{{- define "hull.configMapName" -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- $fullname := .fullname -}}
{{- if and $name (hasKey ($root.Values.configMaps | default dict) $name) }}
{{- printf "%s-%s" $fullname $name }}
{{- else }}
{{- $name }}
{{- end }}
{{- end }}

{{/*
Generate environment variables from an env map.
Supports plain values, secretKeyRef, and configMapKeyRef.
*/}}
{{- define "hull.env" -}}
{{- $env := .env | default dict }}
{{- $root := .root }}
{{- $fullname := .fullname }}
{{- range $key, $val := $env }}
{{- if kindIs "map" $val }}
{{- if hasKey $val "secretKeyRef" }}
- name: {{ $key | quote }}
  valueFrom:
    secretKeyRef:
      name: {{ $val.secretKeyRef.name | quote }}
      key: {{ $val.secretKeyRef.key | quote }}
      {{- if hasKey $val.secretKeyRef "optional" }}
      optional: {{ $val.secretKeyRef.optional }}
      {{- end }}
{{- else if hasKey $val "configMapKeyRef" }}
- name: {{ $key | quote }}
  valueFrom:
    configMapKeyRef:
      name: {{ include "hull.configMapName" (dict "root" $root "name" $val.configMapKeyRef.name "fullname" $fullname) | quote }}
      key: {{ $val.configMapKeyRef.key | quote }}
      {{- if hasKey $val.configMapKeyRef "optional" }}
      optional: {{ $val.configMapKeyRef.optional }}
      {{- end }}
{{- else if hasKey $val "fieldRef" }}
- name: {{ $key | quote }}
  valueFrom:
    fieldRef:
      fieldPath: {{ $val.fieldRef.fieldPath | quote }}
{{- end }}
{{- else }}
- name: {{ $key | quote }}
  value: {{ $val | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate envFrom entries from a list.
Supports secretRef and configMapRef.
*/}}
{{- define "hull.envFrom" -}}
{{- $envFrom := .envFrom | default list }}
{{- $root := .root }}
{{- $fullname := .fullname }}
{{- range $entry := $envFrom }}
{{- if hasKey $entry "secretRef" }}
- secretRef:
    name: {{ $entry.secretRef.name | quote }}
    {{- if hasKey $entry.secretRef "optional" }}
    optional: {{ $entry.secretRef.optional }}
    {{- end }}
{{- else if hasKey $entry "configMapRef" }}
- configMapRef:
    name: {{ include "hull.configMapName" (dict "root" $root "name" $entry.configMapRef.name "fullname" $fullname) | quote }}
    {{- if hasKey $entry.configMapRef "optional" }}
    optional: {{ $entry.configMapRef.optional }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Determine if a port is "http-like" by name or number.
Returns "true" or "false".
*/}}
{{- define "hull.isHttpPort" -}}
{{- $name := .name | default "" | lower }}
{{- $port := .containerPort | default 0 | int }}
{{- if or (hasPrefix "http" $name) (eq $name "web") (eq $name "www") (eq $name "main") (eq $port 80) (eq $port 443) (eq $port 8080) (eq $port 8443) (eq $port 3000) (eq $port 8000) -}}
true
{{- else -}}
false
{{- end -}}
{{- end }}

{{/*
Generate a probe spec for a container.
Accepts a dict:
  - probeConfig: the user probe config (liveness/readiness/startup section)
  - port: the first port dict of the container
  - isStartup: bool, true for startup probes (uses generous defaults)
*/}}
{{- define "hull.probe" -}}
{{- $cfg := .probeConfig | default dict }}
{{- $port := .port | default dict }}
{{- $isStartup := .isStartup | default false }}
{{- $enabled := true }}
{{- if hasKey $cfg "enabled" }}
{{- $enabled = $cfg.enabled }}
{{- end }}
{{- if and $enabled $port }}
{{- $probeType := $cfg.type | default "auto" }}
{{- $portRef := $cfg.port | default ($port.name | default ($port.containerPort | toString)) }}
{{- $isHttp := "false" }}
{{- if eq $probeType "auto" }}
{{- $isHttp = include "hull.isHttpPort" $port }}
{{- else if eq $probeType "http" }}
{{- $isHttp = "true" }}
{{- end }}
{{- if and (eq $probeType "exec") $cfg.command }}
exec:
  command:
    {{- range $cfg.command }}
    - {{ . | quote }}
    {{- end }}
{{- else if eq $isHttp "true" }}
httpGet:
  path: {{ $cfg.path | default "/" }}
  port: {{ $portRef }}
{{- else }}
tcpSocket:
  port: {{ $portRef }}
{{- end }}
initialDelaySeconds: {{ $cfg.initialDelaySeconds | default 0 }}
periodSeconds: {{ $cfg.periodSeconds | default (ternary 5 10 $isStartup) }}
timeoutSeconds: {{ $cfg.timeoutSeconds | default 5 }}
failureThreshold: {{ $cfg.failureThreshold | default (ternary 30 3 $isStartup) }}
successThreshold: {{ $cfg.successThreshold | default 1 }}
{{- end }}
{{- end }}

{{/*
Resolve security context for a container based on securityPreset.
Returns the merged security context.
*/}}
{{- define "hull.containerSecurityContext" -}}
{{- $preset := .preset | default "default" }}
{{- $override := .securityContext | default dict }}
{{- if and (eq $preset "default") (not $override) }}
{{- /* No security context at all */ -}}
{{- else if eq $preset "restricted" }}
{{- $base := dict "runAsNonRoot" true "readOnlyRootFilesystem" true "allowPrivilegeEscalation" false "capabilities" (dict "drop" (list "ALL")) }}
{{- $merged := merge $override $base }}
{{- toYaml $merged }}
{{- else if eq $preset "root" }}
{{- $base := dict "runAsUser" 0 "runAsGroup" 0 }}
{{- $merged := merge $override $base }}
{{- toYaml $merged }}
{{- else }}
{{- if $override }}
{{- toYaml $override }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Return the normalized port list for a container.
*/}}
{{- define "hull.containerPorts" -}}
{{- $root := .root -}}
{{- $containerName := .containerName | default "main" -}}
{{- $ports := list -}}
{{- if eq $containerName "main" }}
{{- range ($root.Values.ports | default list) }}
{{- $ports = append $ports (dict "name" (.name | default "http") "containerPort" .containerPort "protocol" (.protocol | default "TCP")) }}
{{- end }}
{{- else }}
{{- $sidecar := index ($root.Values.sidecars | default dict) $containerName | default dict -}}
{{- if $sidecar.ports }}
{{- range $sidecar.ports }}
{{- $ports = append $ports (dict "name" (.name | default $containerName) "containerPort" .containerPort "protocol" (.protocol | default "TCP")) }}
{{- end }}
{{- else if $sidecar.port }}
{{- $ports = append $ports (dict "name" $containerName "containerPort" ($sidecar.port | int) "protocol" "TCP") }}
{{- end }}
{{- end }}
{{- if $ports }}
{{- toYaml $ports }}
{{- end }}
{{- end }}

{{/*
Generate volume mounts for a container from persistence config.
Accepts a dict:
  - persistence: the persistence map
  - containerName: name of the current container ("main" for main)
  - fullname: the release fullname
*/}}
{{- define "hull.volumeMounts" -}}
{{- $persistence := .persistence | default dict }}
{{- $containerName := .containerName }}
{{- $fullname := .fullname }}
{{- range $name, $vol := $persistence }}
{{- $containers := $vol.containers | default list }}
{{- $mountInThis := true }}
{{- if $containers }}
{{- $mountInThis = has $containerName $containers }}
{{- end }}
{{- if $mountInThis }}
- name: {{ $name }}
  mountPath: {{ $vol.mountPath }}
  {{- if $vol.subPath }}
  subPath: {{ $vol.subPath }}
  {{- end }}
  {{- if $vol.readOnly }}
  readOnly: {{ $vol.readOnly }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate volumes from persistence config.
Accepts a dict:
  - persistence: the persistence map
  - fullname: the release fullname
*/}}
{{- define "hull.volumes" -}}
{{- $persistence := .persistence | default dict }}
{{- $fullname := .fullname }}
{{- range $name, $vol := $persistence }}
{{- $type := $vol.type | default "pvc" }}
{{- if ne $type "volumeClaimTemplate" }}
- name: {{ $name }}
  {{- if eq $type "pvc" }}
  persistentVolumeClaim:
    claimName: {{ $vol.existingClaim | default (printf "%s-%s" $fullname $name) }}
  {{- else if eq $type "emptyDir" }}
  emptyDir:
    {{- if $vol.medium }}
    medium: {{ $vol.medium }}
    {{- end }}
    {{- if $vol.sizeLimit }}
    sizeLimit: {{ $vol.sizeLimit }}
    {{- end }}
  {{- else if eq $type "nfs" }}
  nfs:
    server: {{ $vol.server }}
    path: {{ $vol.path }}
    {{- if $vol.readOnly }}
    readOnly: {{ $vol.readOnly }}
    {{- end }}
  {{- else if eq $type "configmap" }}
  configMap:
    name: {{ $fullname }}-{{ $vol.objectName }}
    {{- if $vol.items }}
    items:
      {{- range $vol.items }}
      - key: {{ .key }}
        path: {{ .path }}
      {{- end }}
    {{- end }}
  {{- else if eq $type "secret" }}
  secret:
    secretName: {{ $vol.objectName }}
    {{- if $vol.items }}
    items:
      {{- range $vol.items }}
      - key: {{ .key }}
        path: {{ .path }}
      {{- end }}
    {{- end }}
  {{- else if eq $type "hostPath" }}
  hostPath:
    path: {{ $vol.hostPath }}
    {{- if $vol.hostPathType }}
    type: {{ $vol.hostPathType }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate StatefulSet volumeClaimTemplates from persistence config.
*/}}
{{- define "hull.volumeClaimTemplates" -}}
{{- $persistence := .persistence | default dict }}
{{- $labels := .labels }}
{{- range $name, $vol := $persistence }}
{{- if eq ($vol.type | default "pvc") "volumeClaimTemplate" }}
- metadata:
    name: {{ $name }}
    labels:
      {{- $labels | nindent 6 }}
      {{- with $vol.labels }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- with $vol.annotations }}
    annotations:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  spec:
    accessModes:
      - {{ $vol.accessMode | default "ReadWriteOnce" }}
    {{- if $vol.storageClass }}
    storageClassName: {{ $vol.storageClass }}
    {{- end }}
    resources:
      requests:
        storage: {{ $vol.size | default "1Gi" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate Authentik forward-auth annotations for nginx ingress.
Accepts a dict with "hostname" and "outpost" keys.
*/}}
{{- define "hull.authentikAnnotations" -}}
{{- $outpost := .outpost | default "http://ak-outpost-authentik-embedded-outpost.authentik.svc.cluster.local:9000" -}}
nginx.ingress.kubernetes.io/auth-url: "{{ $outpost }}/outpost.goauthentik.io/auth/nginx"
nginx.ingress.kubernetes.io/auth-signin: "https://{{ .hostname }}/outpost.goauthentik.io/start?rd=$escaped_request_uri"
nginx.ingress.kubernetes.io/auth-response-headers: "Set-Cookie,X-authentik-username,X-authentik-groups,X-authentik-email,X-authentik-name,X-authentik-uid"
nginx.ingress.kubernetes.io/auth-snippet: |
  proxy_set_header X-Forwarded-Host $http_host;
nginx.ingress.kubernetes.io/server-snippet: |
  location /outpost.goauthentik.io {
    proxy_pass {{ $outpost }}/outpost.goauthentik.io;
    proxy_set_header Host $host;
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
  }
{{- end }}

{{/*
Resolve the target container for a service entry.
*/}}
{{- define "hull.serviceTargetContainer" -}}
{{- if .svcConfig.targetContainer -}}
{{- .svcConfig.targetContainer -}}
{{- else if eq .serviceName "main" -}}
main
{{- else -}}
{{- .serviceName -}}
{{- end -}}
{{- end }}

{{/*
Generate the rendered Service port list.
Outputs YAML list directly — avoids Helm 4 scoping issues with $var reassignment.
*/}}
{{- define "hull.servicePorts" -}}
{{- $root := .root -}}
{{- $serviceName := .serviceName -}}
{{- $svcConfig := .svcConfig | default dict -}}
{{- $targetContainer := include "hull.serviceTargetContainer" (dict "serviceName" $serviceName "svcConfig" $svcConfig) -}}
{{- $containerPorts := include "hull.containerPorts" (dict "root" $root "containerName" $targetContainer) | fromYamlArray | default list -}}
{{- if and (eq $targetContainer "main") $svcConfig.ports }}
{{- include "hull.servicePortsMultiMain" (dict "root" $root "svcConfig" $svcConfig) }}
{{- else if $svcConfig.ports }}
{{- include "hull.servicePortsMultiSidecar" (dict "svcConfig" $svcConfig "containerPorts" $containerPorts) }}
{{- else if eq $targetContainer "main" }}
{{- include "hull.servicePortsSingleMain" (dict "root" $root "svcConfig" $svcConfig) }}
{{- else }}
{{- include "hull.servicePortsSingleSidecar" (dict "svcConfig" $svcConfig "containerPorts" $containerPorts) }}
{{- end }}
{{- end }}

{{- define "hull.servicePortsMultiMain" -}}
{{- $root := .root -}}
{{- $svcConfig := .svcConfig -}}
{{- $result := list -}}
{{- range $portKey, $portConfig := $svcConfig.ports }}
{{- $matchedPort := dict -}}
{{- range ($root.Values.ports | default list) }}
{{- if eq (.name | default "") $portKey }}
{{- $matchedPort = . }}
{{- end }}
{{- end }}
{{- $servicePort := $portConfig.port | default ($matchedPort.containerPort | default nil) -}}
{{- $targetPort := $portConfig.targetPort | default ($matchedPort.name | default ($matchedPort.containerPort | default $servicePort)) -}}
{{- if $servicePort }}
{{- $item := dict "name" ($portConfig.name | default $portKey) "port" $servicePort "targetPort" $targetPort "protocol" ($portConfig.protocol | default ($matchedPort.protocol | default "TCP")) -}}
{{- if $portConfig.nodePort }}{{- $item = merge $item (dict "nodePort" $portConfig.nodePort) }}{{- end }}
{{- if $portConfig.appProtocol }}{{- $item = merge $item (dict "appProtocol" $portConfig.appProtocol) }}{{- end }}
{{- $result = append $result $item }}
{{- end }}
{{- end }}
{{- if $result }}{{ toYaml $result }}{{ end }}
{{- end }}

{{- define "hull.servicePortsMultiSidecar" -}}
{{- $svcConfig := .svcConfig -}}
{{- $containerPorts := .containerPorts -}}
{{- $result := list -}}
{{- range $portKey, $portConfig := $svcConfig.ports }}
{{- $matchedPort := dict -}}
{{- range $containerPorts }}
{{- if eq (.name | default "") $portKey }}
{{- $matchedPort = . }}
{{- end }}
{{- end }}
{{- $mCP := "" -}}{{- if hasKey $matchedPort "containerPort" }}{{- $mCP = index $matchedPort "containerPort" -}}{{- end }}
{{- $mN := "" -}}{{- if hasKey $matchedPort "name" }}{{- $mN = index $matchedPort "name" -}}{{- end }}
{{- $mP := "" -}}{{- if hasKey $matchedPort "protocol" }}{{- $mP = index $matchedPort "protocol" -}}{{- end }}
{{- $servicePort := $portConfig.port | default ($mCP | default nil) -}}
{{- $targetPort := $portConfig.targetPort | default ($mN | default ($mCP | default $servicePort)) -}}
{{- if $servicePort }}
{{- $item := dict "name" ($portConfig.name | default $portKey) "port" $servicePort "targetPort" $targetPort "protocol" ($portConfig.protocol | default ($mP | default "TCP")) -}}
{{- if $portConfig.nodePort }}{{- $item = merge $item (dict "nodePort" $portConfig.nodePort) }}{{- end }}
{{- if $portConfig.appProtocol }}{{- $item = merge $item (dict "appProtocol" $portConfig.appProtocol) }}{{- end }}
{{- $result = append $result $item }}
{{- end }}
{{- end }}
{{- if $result }}{{ toYaml $result }}{{ end }}
{{- end }}

{{- define "hull.servicePortsSingleMain" -}}
{{- $root := .root -}}
{{- $svcConfig := .svcConfig -}}
{{- $mainPorts := $root.Values.ports | default list -}}
{{- if gt (len $mainPorts) 0 -}}
{{- $servicePort := $svcConfig.port | default (index $mainPorts 0).containerPort -}}
{{- $portName := $svcConfig.name | default ((index $mainPorts 0).name | default "http") -}}
{{- $targetPort := $svcConfig.targetPort | default ((index $mainPorts 0).name | default (index $mainPorts 0).containerPort) -}}
{{- $protocol := $svcConfig.protocol | default ((index $mainPorts 0).protocol | default "TCP") -}}
{{- toYaml (list (dict "name" $portName "port" $servicePort "targetPort" $targetPort "protocol" $protocol)) }}
{{- else if $svcConfig.port -}}
{{- toYaml (list (dict "name" ($svcConfig.name | default "http") "port" $svcConfig.port "targetPort" ($svcConfig.targetPort | default $svcConfig.port) "protocol" ($svcConfig.protocol | default "TCP"))) }}
{{- end -}}
{{- end }}

{{- define "hull.servicePortsSingleSidecar" -}}
{{- $svcConfig := .svcConfig -}}
{{- $containerPorts := .containerPorts -}}
{{- $fCP := "" -}}
{{- $fN := "" -}}
{{- $fP := "" -}}
{{- if gt (len $containerPorts) 0 }}
{{- $fp := index $containerPorts 0 -}}
{{- if hasKey $fp "containerPort" }}{{- $fCP = index $fp "containerPort" -}}{{- end }}
{{- if hasKey $fp "name" }}{{- $fN = index $fp "name" -}}{{- end }}
{{- if hasKey $fp "protocol" }}{{- $fP = index $fp "protocol" -}}{{- end }}
{{- end }}
{{- $servicePort := $svcConfig.port | default ($fCP | default nil) -}}
{{- if $servicePort }}
{{- $targetPort := $svcConfig.targetPort | default ($fN | default ($fCP | default $servicePort)) -}}
{{- $item := dict "name" ($svcConfig.name | default ($fN | default "http")) "port" $servicePort "targetPort" $targetPort "protocol" ($svcConfig.protocol | default ($fP | default "TCP")) -}}
{{- if $svcConfig.nodePort }}{{- $item = merge $item (dict "nodePort" $svcConfig.nodePort) }}{{- end }}
{{- toYaml (list $item) }}
{{- end }}
{{- end }}

{{/*
Return the first rendered Service port number.
*/}}
{{- define "hull.servicePort" -}}
{{- $ports := include "hull.servicePorts" . | fromYamlArray | default list -}}
{{- if gt (len $ports) 0 }}
{{- (index $ports 0).port }}
{{- end }}
{{- end }}

{{/*
Return the first rendered Service port name.
*/}}
{{- define "hull.servicePortName" -}}
{{- $ports := include "hull.servicePorts" . | fromYamlArray | default list -}}
{{- if gt (len $ports) 0 }}
{{- (index $ports 0).name }}
{{- end }}
{{- end }}

{{/*
Return the secret name for a database entry.
Accepts a dict:
  - db: the database config map
  - dbName: the key name of the database entry
  - fullname: the release fullname
*/}}
{{- define "hull.databaseSecretName" -}}
{{- $db := .db -}}
{{- $dbName := .dbName -}}
{{- $fullname := .fullname -}}
{{- $type := $db.type | default "cnpg" -}}
{{- if eq $type "cnpg" -}}
  {{- if and $db.pooler (ne (toString (index ($db.pooler | default dict) "usePoolerConnection" | default true)) "false") -}}
    {{- printf "%s-%s-pooler" $fullname $dbName -}}
  {{- else -}}
    {{- printf "%s-%s-app" $fullname $dbName -}}
  {{- end -}}
{{- else if eq $type "crossplane" -}}
  {{- printf "%s-%s-conn" $fullname $dbName -}}
{{- else if eq $type "external" -}}
  {{- $db.secretName -}}
{{- end -}}
{{- end }}

{{/*
Generate database environment variables for a specific container.
Accepts a dict:
  - databases: the .Values.database map
  - containerName: name of the container ("main", sidecar name, or init container name)
  - fullname: the release fullname
  - isInitContainer: bool, true when generating for init containers
*/}}
{{- define "hull.databaseEnv" -}}
{{- $databases := .databases | default dict -}}
{{- $containerName := .containerName -}}
{{- $fullname := .fullname -}}
{{- $isInitContainer := .isInitContainer | default false -}}
{{- range $dbName, $db := $databases -}}
{{- $env := $db.env | default dict -}}
{{- if $env -}}
{{- $inject := false -}}
{{- if $isInitContainer -}}
  {{- if $db.injectIntoInitContainers -}}
    {{- $inject = true -}}
  {{- end -}}
{{- else -}}
  {{- $containers := $db.containers | default list -}}
  {{- if not $containers -}}
    {{- if eq $containerName "main" -}}
      {{- $inject = true -}}
    {{- end -}}
  {{- else -}}
    {{- if has $containerName $containers -}}
      {{- $inject = true -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if $inject -}}
{{- $secretName := include "hull.databaseSecretName" (dict "db" $db "dbName" $dbName "fullname" $fullname) -}}
{{- range $envKey, $secretKey := $env }}
- name: {{ $envKey | quote }}
  valueFrom:
    secretKeyRef:
      name: {{ $secretName | quote }}
      key: {{ $secretKey | quote }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Pod template shared by every workload kind.

Extracted so Deployment, StatefulSet, DaemonSet, Job and CronJob render one
identical pod spec instead of four drifting copies. Emitted at indent 0; the
caller nindents it (2 for the apps/v1 kinds and Job, 6 under CronJob
jobTemplate). Scope variables the block needs are recomputed here because a
define does not inherit the caller's $vars.
*/}}
{{- define "hull.podTemplate" -}}
{{- $fullname := include "hull.fullname" . -}}
{{- $selectorLabels := include "hull.selectorLabels" . -}}
{{- $kind := .Values.workloadType | default "Deployment" -}}
template:
  metadata:
    labels:
      {{- $selectorLabels | nindent 6 }}
      {{- with .Values.podLabels }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- if or .Values.podAnnotations .Values.configMaps }}
    annotations:
      {{- /* Roll the pods whenever a chart-rendered ConfigMap changes; without
           this a config-only edit needs a manual rollout restart. */}}
      {{- with .Values.configMaps }}
      checksum/configmaps: {{ toYaml . | sha256sum }}
      {{- end }}
      {{- with .Values.podAnnotations }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- end }}
  spec:
    {{- with .Values.imagePullSecrets }}
    imagePullSecrets:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- if or .Values.serviceAccount.create .Values.serviceAccount.name }}
    serviceAccountName: {{ include "hull.serviceAccountName" . }}
    {{- end }}
    {{- if .Values.priorityClassName }}
    priorityClassName: {{ .Values.priorityClassName }}
    {{- end }}
    {{- if .Values.hostNetwork }}
    hostNetwork: true
    {{- end }}
    {{- if .Values.dnsPolicy }}
    dnsPolicy: {{ .Values.dnsPolicy }}
    {{- end }}
    {{- with .Values.dnsConfig }}
    dnsConfig:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds | default 30 }}
    {{- /* Kubernetes rejects restartPolicy Always on Job and CronJob pods.
         values.yaml carries Always as the chart-wide default, so `default`
         cannot tell "chart default" from "user asked for Always" -- and since
         Always is invalid for batch kinds either way, coerce it to OnFailure
         rather than render a manifest the API server will refuse. An explicit
         Never or OnFailure is still honoured. */}}
    {{- $restartPolicy := .Values.restartPolicy | default "Always" -}}
    {{- if and (has $kind (list "Job" "CronJob")) (eq $restartPolicy "Always") -}}
    {{- $restartPolicy = "OnFailure" -}}
    {{- end }}
    restartPolicy: {{ $restartPolicy }}
    {{- /* Pod security context */ -}}
    {{- $podSec := .Values.podSecurityContext | default dict }}
    {{- $preset := .Values.securityPreset | default "default" }}
    {{- if ne (len $podSec) 0 }}
    securityContext:
      {{- toYaml $podSec | nindent 6 }}
    {{- end }}
    {{- /* Init containers */ -}}
    {{- if .Values.initContainers }}
    initContainers:
      {{- range $name, $init := .Values.initContainers }}
      - name: {{ $name }}
        image: {{ include "hull.image" $init.image }}
        imagePullPolicy: {{ $init.image.pullPolicy | default "IfNotPresent" }}
        {{- with $init.command }}
        command:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with $init.args }}
        args:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- $initDbEnv := include "hull.databaseEnv" (dict "databases" $.Values.database "containerName" $name "fullname" $fullname "isInitContainer" true) | trim }}
        {{- if or $init.env $initDbEnv }}
        env:
          {{- if $init.env }}
          {{- include "hull.env" (dict "env" $init.env "root" $ "fullname" $fullname) | trim | nindent 10 }}
          {{- end }}
          {{- if $initDbEnv }}
          {{- $initDbEnv | nindent 10 }}
          {{- end }}
        {{- end }}
        {{- if $init.envFrom }}
        envFrom:
          {{- include "hull.envFrom" (dict "envFrom" $init.envFrom "root" $ "fullname" $fullname) | trim | nindent 10 }}
        {{- end }}
        {{- with $init.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with $init.securityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- $initMounts := include "hull.volumeMounts" (dict "persistence" $.Values.persistence "containerName" $name "fullname" $fullname) }}
        {{- $extraMounts := $init.volumeMounts | default list }}
        {{- if or $initMounts $extraMounts }}
        volumeMounts:
          {{- if $initMounts }}
          {{- $initMounts | trim | nindent 10 }}
          {{- end }}
          {{- range $extraMounts }}
          - {{ toYaml . | nindent 12 | trim }}
          {{- end }}
        {{- end }}
      {{- end }}
    {{- end }}
    containers:
      - name: main
        image: {{ include "hull.image" .Values.image }}
        imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
        {{- with .Values.command }}
        command:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with .Values.args }}
        args:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- $mainDbEnv := include "hull.databaseEnv" (dict "databases" .Values.database "containerName" "main" "fullname" $fullname) | trim }}
        {{- if or .Values.env $mainDbEnv }}
        env:
          {{- if .Values.env }}
          {{- include "hull.env" (dict "env" .Values.env "root" . "fullname" $fullname) | trim | nindent 10 }}
          {{- end }}
          {{- if $mainDbEnv }}
          {{- $mainDbEnv | nindent 10 }}
          {{- end }}
        {{- end }}
        {{- if .Values.envFrom }}
        envFrom:
          {{- include "hull.envFrom" (dict "envFrom" .Values.envFrom "root" . "fullname" $fullname) | trim | nindent 10 }}
        {{- end }}
        {{- if .Values.ports }}
        ports:
          {{- range .Values.ports }}
          - name: {{ .name | default "http" }}
            containerPort: {{ .containerPort }}
            {{- if .hostPort }}
            hostPort: {{ .hostPort }}
            {{- end }}
            protocol: {{ .protocol | default "TCP" }}
          {{- end }}
        {{- end }}
        {{- /* Probes */ -}}
        {{- $probesEnabled := true }}
        {{- if hasKey .Values.probes "enabled" }}
        {{- $probesEnabled = .Values.probes.enabled }}
        {{- end }}
        {{- $firstPort := dict }}
        {{- if .Values.ports }}
        {{- $firstPort = index .Values.ports 0 }}
        {{- end }}
        {{- if and $probesEnabled $firstPort }}
        {{- $livenessProbe := include "hull.probe" (dict "probeConfig" .Values.probes.liveness "port" $firstPort "isStartup" false) | trim }}
        {{- if $livenessProbe }}
        livenessProbe:
          {{- $livenessProbe | nindent 10 }}
        {{- end }}
        {{- $readinessProbe := include "hull.probe" (dict "probeConfig" .Values.probes.readiness "port" $firstPort "isStartup" false) | trim }}
        {{- if $readinessProbe }}
        readinessProbe:
          {{- $readinessProbe | nindent 10 }}
        {{- end }}
        {{- $startupProbe := include "hull.probe" (dict "probeConfig" .Values.probes.startup "port" $firstPort "isStartup" true) | trim }}
        {{- if $startupProbe }}
        startupProbe:
          {{- $startupProbe | nindent 10 }}
        {{- end }}
        {{- end }}
        {{- with .Values.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- $mainSec := include "hull.containerSecurityContext" (dict "preset" $preset "securityContext" .Values.securityContext) }}
        {{- if $mainSec }}
        securityContext:
          {{- $mainSec | nindent 10 }}
        {{- end }}
        {{- with .Values.lifecycle }}
        lifecycle:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- $mainMounts := include "hull.volumeMounts" (dict "persistence" .Values.persistence "containerName" "main" "fullname" $fullname) }}
        {{- $extraMounts := .Values.volumeMounts | default list }}
        {{- if or $mainMounts $extraMounts }}
        volumeMounts:
          {{- if $mainMounts }}
          {{- $mainMounts | trim | nindent 10 }}
          {{- end }}
          {{- range $extraMounts }}
          - {{ toYaml . | nindent 12 | trim }}
          {{- end }}
        {{- end }}
      {{- /* ---- Sidecar containers ---- */ -}}
      {{- range $name, $sidecar := .Values.sidecars }}
      - name: {{ $name }}
        image: {{ include "hull.image" $sidecar.image }}
        imagePullPolicy: {{ $sidecar.image.pullPolicy | default "IfNotPresent" }}
        {{- with $sidecar.command }}
        command:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with $sidecar.args }}
        args:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- $sidecarDbEnv := include "hull.databaseEnv" (dict "databases" $.Values.database "containerName" $name "fullname" $fullname) | trim }}
        {{- if or $sidecar.env $sidecarDbEnv }}
        env:
          {{- if $sidecar.env }}
          {{- include "hull.env" (dict "env" $sidecar.env "root" $ "fullname" $fullname) | trim | nindent 10 }}
          {{- end }}
          {{- if $sidecarDbEnv }}
          {{- $sidecarDbEnv | nindent 10 }}
          {{- end }}
        {{- end }}
        {{- if $sidecar.envFrom }}
        envFrom:
          {{- include "hull.envFrom" (dict "envFrom" $sidecar.envFrom "root" $ "fullname" $fullname) | trim | nindent 10 }}
        {{- end }}
        {{- /* Sidecar ports: support single port shorthand or full ports list */ -}}
        {{- $sidecarPorts := include "hull.containerPorts" (dict "root" $ "containerName" $name) | fromYamlArray | default list }}
        {{- if $sidecarPorts }}
        ports:
          {{- range $sidecarPorts }}
          - name: {{ .name | default $name }}
            containerPort: {{ .containerPort }}
            {{- if .hostPort }}
            hostPort: {{ .hostPort }}
            {{- end }}
            protocol: {{ .protocol | default "TCP" }}
          {{- end }}
        {{- end }}
        {{- /* Sidecar probes */ -}}
        {{- $sProbesEnabled := true }}
        {{- $sProbes := $sidecar.probes | default dict }}
        {{- if hasKey $sProbes "enabled" }}
        {{- $sProbesEnabled = $sProbes.enabled }}
        {{- end }}
        {{- $sFirstPort := dict }}
        {{- if $sidecarPorts }}
        {{- $sFirstPort = index $sidecarPorts 0 }}
        {{- end }}
        {{- if and $sProbesEnabled $sFirstPort }}
        {{- $sLiveness := include "hull.probe" (dict "probeConfig" $sProbes.liveness "port" $sFirstPort "isStartup" false) | trim }}
        {{- if $sLiveness }}
        livenessProbe:
          {{- $sLiveness | nindent 10 }}
        {{- end }}
        {{- $sReadiness := include "hull.probe" (dict "probeConfig" $sProbes.readiness "port" $sFirstPort "isStartup" false) | trim }}
        {{- if $sReadiness }}
        readinessProbe:
          {{- $sReadiness | nindent 10 }}
        {{- end }}
        {{- $sStartup := include "hull.probe" (dict "probeConfig" $sProbes.startup "port" $sFirstPort "isStartup" true) | trim }}
        {{- if $sStartup }}
        startupProbe:
          {{- $sStartup | nindent 10 }}
        {{- end }}
        {{- end }}
        {{- with $sidecar.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- $sSec := include "hull.containerSecurityContext" (dict "preset" $preset "securityContext" $sidecar.securityContext) }}
        {{- if $sSec }}
        securityContext:
          {{- $sSec | nindent 10 }}
        {{- end }}
        {{- with $sidecar.lifecycle }}
        lifecycle:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- $sMounts := include "hull.volumeMounts" (dict "persistence" $.Values.persistence "containerName" $name "fullname" $fullname) }}
        {{- $sExtraMounts := $sidecar.volumeMounts | default list }}
        {{- if or $sMounts $sExtraMounts }}
        volumeMounts:
          {{- if $sMounts }}
          {{- $sMounts | trim | nindent 10 }}
          {{- end }}
          {{- range $sExtraMounts }}
          - {{ toYaml . | nindent 12 | trim }}
          {{- end }}
        {{- end }}
      {{- end }}
    {{- $volumes := include "hull.volumes" (dict "persistence" .Values.persistence "fullname" $fullname) | trim }}
    {{- if $volumes }}
    volumes:
      {{- $volumes | nindent 6 }}
    {{- end }}
    {{- with .Values.nodeSelector }}
    nodeSelector:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.affinity }}
    affinity:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.tolerations }}
    tolerations:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.topologySpreadConstraints }}
    topologySpreadConstraints:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}

{{/*
Job spec fields shared by workloadType Job and CronJob's jobTemplate.
Emitted at indent 0; the caller nindents (2 for Job, 6 under jobTemplate).
*/}}
{{- define "hull.jobSpecFields" -}}
{{- $job := .Values.job | default dict -}}
{{- if not (kindIs "invalid" $job.backoffLimit) }}
backoffLimit: {{ $job.backoffLimit }}
{{- end }}
{{- if not (kindIs "invalid" $job.completions) }}
completions: {{ $job.completions }}
{{- end }}
{{- if not (kindIs "invalid" $job.parallelism) }}
parallelism: {{ $job.parallelism }}
{{- end }}
{{- if not (kindIs "invalid" $job.activeDeadlineSeconds) }}
activeDeadlineSeconds: {{ $job.activeDeadlineSeconds }}
{{- end }}
{{- if not (kindIs "invalid" $job.ttlSecondsAfterFinished) }}
ttlSecondsAfterFinished: {{ $job.ttlSecondsAfterFinished }}
{{- end }}
{{- end }}

