{{/*
Expand the name of the chart.
*/}}
{{- define "chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "chart.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "chart.labels" -}}
helm.sh/chart: {{ include "chart.chart" . }}
{{ include "chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "chart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate the comma-separated CUBESTORE_WORKERS list.
Produces: cubestore-worker-0.cubestore-worker:<port>,cubestore-worker-1.cubestore-worker:<port>,...
*/}}
{{- define "chart.cubestoreWorkers" -}}
{{- $port := .Values.cubestoreWorker.service.port -}}
{{- $workers := list -}}
{{- range $i := until (.Values.cubestoreWorker.replicas | int) -}}
{{- $workers = append $workers (printf "cubestore-worker-%d.cubestore-worker:%v" $i $port) -}}
{{- end -}}
{{- join "," $workers -}}
{{- end }}

{{/*
Readiness probe: /readyz, then /meta. /readyz only checks the BigQuery and Cube Store
connections, so it stays green when the schema fails to load (e.g. "Found duplicate cube name"
on Cube 1.7). /meta compiles the model; it's called with a short-lived token signed with CUBEJS_API_SECRET.
fullProjectIds is needed so contextToGroups yields a group; without it /meta returns 0 cubes.
Passes on >=1 cube and no duplicate names.
Usage: {{ include "chart.schemaReadinessProbe" .Values.cubeApi.service.port }}
*/}}
{{- define "chart.schemaReadinessProbe" -}}
exec:
  command:
    - node
    - -e
    - |
      const c=require('crypto'),b=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
      const h=b({alg:'HS256',typ:'JWT'})+'.'+b({params:{fullProjectIds:['readiness-probe']},exp:Math.floor(Date.now()/1e3)+60});
      const t=h+'.'+c.createHmac('sha256',process.env.CUBEJS_API_SECRET).update(h).digest('base64url');
      const u='http://localhost:{{ . }}',o={signal:AbortSignal.timeout(4000)};
      fetch(u+'/readyz',o).then(r=>{if(!r.ok)throw new Error('readyz '+r.status);
          return fetch(u+'/cubejs-api/v1/meta',{...o,headers:{Authorization:t}})})
        .then(async r=>{const j=await r.json().catch(()=>({}));const n=(j.cubes||[]).map(x=>x.name);
          const ok=r.ok&&!j.error&&n.length>0&&new Set(n).size===n.length;
          console.log(r.status,j.error?String(j.error).slice(0,200):'cubes='+n.length);process.exit(ok?0:1)})
        .catch(e=>{console.log('ERR',e.message);process.exit(1)});
initialDelaySeconds: 20
periodSeconds: 30
timeoutSeconds: 5
failureThreshold: 3
{{- end }}


{{/*
Cube Store only refreshes IRSA credentials before they expire when these two variables are set
(remotefs/s3.rs at v1.7.46, L65-66). It ignores the AWS_ROLE_ARN / AWS_WEB_IDENTITY_TOKEN_FILE that
EKS injects; with only those, it refreshes every 180 min while the STS session lasts 60, so uploads
fail two hours in three. Derived from the service account's IRSA annotation, so no new value to set.
*/}}
{{- define "chart.cubestoreWebIdentityEnv" -}}
{{- with index .Values.serviceAccount.annotations "eks.amazonaws.com/role-arn" }}
CUBESTORE_AWS_ROLE_ARN: {{ . | quote }}
CUBESTORE_AWS_WEB_IDENTITY_TOKEN_FILE: "/var/run/secrets/eks.amazonaws.com/serviceaccount/token"
{{- end }}
{{- end }}
