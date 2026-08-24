{{- define "smartdockershrinker.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "smartdockershrinker.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "smartdockershrinker.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "smartdockershrinker.labels" -}}
app.kubernetes.io/name: {{ include "smartdockershrinker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "smartdockershrinker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "smartdockershrinker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
