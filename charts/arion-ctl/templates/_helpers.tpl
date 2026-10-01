{{- define "arion.name" -}}
{{- printf "%s-controller" .Release.Name | trunc 40 | trimSuffix "-" -}}
{{- end -}}
{{- define "arion.selector" -}}
app.kubernetes.io/name: arion-ctl
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "arion.labelSelector" -}}
{{- $terms := list -}}
{{- range $key, $value := include "arion.selector" . | fromYaml -}}
{{- $terms = append $terms (printf "%s=%v" $key $value) -}}
{{- end -}}
{{- join "," $terms -}}
{{- end -}}
{{- define "arion.cookie" -}}
{{- default (printf "%s-cookie" (include "arion.name" .)) .Values.cookie.existingSecret -}}
{{- end -}}
