{{/*
One chart serves every service on the platform, so names come from the release
rather than the chart. A release named `sample-service` produces resources named
`sample-service`, which is what the catalog, Argo CD and kubectl all show.
*/}}
{{- define "service.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- define "service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "service.labels" -}}
{{ include "service.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: service
app.kubernetes.io/part-of: {{ .Values.partOf | default "idp" }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{/*
A digest pins the exact bytes that were scanned, which a tag cannot do even when
the registry enforces immutability. Promotion writes the digest, so deployments
resolve by digest and the tag remains only for human identification.
*/}}
{{- define "service.image" -}}
{{- $digest := .Values.image.digest | default "" -}}
{{- if $digest -}}
{{- printf "%s@%s" .Values.image.repository $digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | toString) -}}
{{- end -}}
{{- end -}}
