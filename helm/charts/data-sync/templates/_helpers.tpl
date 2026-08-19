{{/*
Shared template helpers. Standard Helm scaffold conventions, plus two
data-sync specific helpers at the bottom (secretName, env).
*/}}

{{- define "data-sync.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name, capped at 63 chars for the label value limit.
*/}}
{{- define "data-sync.fullname" -}}
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

{{- define "data-sync.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Labels on every object. `commonLabels` lets a caller stamp org-wide labels
(cost-center, owner) without touching the chart.
*/}}
{{- define "data-sync.labels" -}}
helm.sh/chart: {{ include "data-sync.chart" . }}
{{ include "data-sync.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: data-sync
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels: immutable across upgrades. Never add anything version-
dependent here - a Deployment's selector is an immutable field.
*/}}
{{- define "data-sync.selectorLabels" -}}
app.kubernetes.io/name: {{ include "data-sync.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Secret holding REDIS_PASSWORD: either the caller's pre-existing
Secret (production, managed by External Secrets) or the one this chart
renders (local only).
*/}}
{{- define "data-sync.secretName" -}}
{{- if .Values.secret.existingSecret }}
{{- .Values.secret.existingSecret }}
{{- else }}
{{- printf "%s-redis" (include "data-sync.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Container image reference. Falls back to Chart.AppVersion when tag is unset.
*/}}
{{- define "data-sync.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}

{{/*
Env block for the app container.

Non-sensitive config comes from the ConfigMap via envFrom (see deployment.yaml).
Only REDIS_PASSWORD is listed explicitly, as a secretKeyRef - deliberately NOT
envFrom on the Secret, so a stray key in that Secret can never silently become
an env var in this container.
*/}}
{{- define "data-sync.env" -}}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "data-sync.secretName" . }}
      key: {{ .Values.secret.key }}
{{- with .Values.app.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
