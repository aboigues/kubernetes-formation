{{/*
Les noms et labels communs à tous les objets du chart. Préfixer par le nom de
la release permet d'installer plusieurs fois le chart dans le même namespace.
*/}}
{{- define "telemarche.nom" -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{- define "telemarche.labels" -}}
app.kubernetes.io/name: telemarche
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* Le durcissement standard du dépôt (expliqué au TP06). */}}
{{- define "telemarche.securite.pod" -}}
runAsNonRoot: true
runAsUser: 65532
runAsGroup: 65532
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "telemarche.securite.conteneur" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}
