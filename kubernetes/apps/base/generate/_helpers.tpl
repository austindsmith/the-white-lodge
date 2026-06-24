{{- define "generate.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "generate.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "generate.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "generate.labels" -}}
app.kubernetes.io/name: {{ include "generate.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "generate.secretName" -}}
{{ include "generate.fullname" . }}-secrets
{{- end -}}

{{- define "generate.connectionString" -}}
{{- $db := index . 0 -}}
{{- $root := index . 1 -}}
Server={{ $root.Values.database.host }},{{ $root.Values.database.port }};Database={{ $db }};User Id={{ $root.Values.database.user }};Password=$(DB_PASSWORD);Encrypt={{ ternary "True" "False" $root.Values.database.encrypt }};TrustServerCertificate={{ ternary "True" "False" $root.Values.database.trustServerCertificate }};
{{- end -}}

{{- define "generate.appEnv" -}}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "generate.secretName" . }}
      key: {{ .Values.database.passwordSecretKey }}
- name: AppSettings__UserStoreType
  value: {{ .Values.app.userStoreType | quote }}
- name: AppSettings__Environment
  value: {{ .Values.app.environment | quote }}
- name: AppSettings__ProvisionJobs
  value: {{ .Values.app.provisionJobs | quote }}
- name: AppSettings__BackgroundUrl
  value: {{ printf "http://%s-background:%v" (include "generate.fullname" .) .Values.background.service.port | quote }}
- name: Data__AppDbContextConnection
  value: {{ include "generate.connectionString" (list .Values.database.names.app .) | quote }}
- name: Data__ODSDbContextConnection
  value: {{ include "generate.connectionString" (list .Values.database.names.ods .) | quote }}
- name: Data__StagingDbContextConnection
  value: {{ include "generate.connectionString" (list .Values.database.names.staging .) | quote }}
- name: Data__RDSDbContextConnection
  value: {{ include "generate.connectionString" (list .Values.database.names.rds .) | quote }}
- name: Data__HangfireConnection
  value: {{ include "generate.connectionString" (list .Values.database.names.hangfire .) | quote }}
- name: AzureAd__Instance
  value: {{ .Values.azureAd.instance | quote }}
- name: AzureAd__Domain
  value: {{ .Values.azureAd.domain | quote }}
- name: AzureAd__TenantId
  value: {{ .Values.azureAd.tenantId | quote }}
- name: AzureAd__ClientId
  value: {{ .Values.azureAd.clientId | quote }}
{{- if .Values.azureAd.clientSecret.enabled }}
- name: AzureAd__ClientSecret
  valueFrom:
    secretKeyRef:
      name: {{ include "generate.secretName" . }}
      key: {{ .Values.azureAd.clientSecret.secretKey }}
{{- end }}
{{- if eq .Values.app.userStoreType "EMBEDDED" }}
- name: AppSettings__EmbeddedAdminUserName
  value: {{ .Values.embedded.adminUserName | quote }}
- name: AppSettings__EmbeddedReviewerUserName
  value: {{ .Values.embedded.reviewerUserName | quote }}
- name: AppSettings__EmbeddedAdminPassword
  valueFrom:
    secretKeyRef:
      name: {{ include "generate.secretName" . }}
      key: {{ .Values.embedded.secretKeys.adminPassword }}
- name: AppSettings__EmbeddedReviewerPassword
  valueFrom:
    secretKeyRef:
      name: {{ include "generate.secretName" . }}
      key: {{ .Values.embedded.secretKeys.reviewerPassword }}
{{- end }}
{{- if .Values.app.forwardedHeaders }}
- name: ASPNETCORE_FORWARDEDHEADERS_ENABLED
  value: "true"
{{- end }}
{{- end -}}
