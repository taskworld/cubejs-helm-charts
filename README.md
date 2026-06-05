# cubejs-helm-charts

Helm chart for deploying [Cube.js](https://cube.dev) on Kubernetes (EKS) with BigQuery as the data source and CubeStore backed by S3 remote storage.

## Components

| Component | Kind | Description |
|-----------|------|-------------|
| `cube-api` | Deployment | Cube.js API server |
| `cube-refresh-worker` | Deployment | Handles pre-aggregation refresh |
| `cubestore-router` | StatefulSet | CubeStore metadata router (single instance) |
| `cubestore-worker` | StatefulSet | CubeStore query workers (scalable) |

## Prerequisites

### 1. Create the namespace manually

The chart does **not** create the namespace. Create it before running `helm install`:

```bash
kubectl create namespace cubejs
```

### 2. Create the K8s Secret

The secret must exist in the namespace **before** deploying the chart. It is referenced by `cubeApi.secret.name` and `cubeRefreshWorker.secret.name` (default: `cubejs-secret`).

Required keys:

| Key | Description |
|-----|-------------|
| `CUBEJS_API_SECRET` | Cryptographically random string (minimum 32 bytes / 64 hex chars) used to sign JWT tokens for API access. Generate with: `openssl rand -hex 32` |
| `CUBEJS_DB_BQ_CREDENTIALS_FILE` | BigQuery service account JSON key (file contents) |
| `CUBEJS_SQL_USER` | **Only when the SQL API is enabled** (`cubeApi.sql.enabled=true`). Arbitrary username SQL clients use to connect over the Postgres protocol. Unrelated to BigQuery auth. |
| `CUBEJS_SQL_PASSWORD` | **Only when the SQL API is enabled.** Arbitrary password for the SQL client connection. |

```bash
kubectl create secret generic cubejs-secret \
  --from-literal=CUBEJS_API_SECRET=$(openssl rand -hex 32) \
  --from-file=CUBEJS_DB_BQ_CREDENTIALS_FILE=sa-key.json \
  -n cubejs
```

### 3. Create S3 bucket for CubeStore

CubeStore uses S3 as shared remote storage for both the router and workers. EBS is not used as it does not support `ReadWriteMany`.

- Create an S3 bucket in the same region as your EKS cluster
- Pass the bucket name and region via `--set cubestore.s3.bucket=... --set cubestore.s3.region=...`

### 4. Configure IRSA for S3 access

CubeStore pods authenticate to S3 via [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) — no static AWS credentials are stored in the cluster.

Create an IAM role with the following policy (replace `BUCKET_NAME`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::BUCKET_NAME",
        "arn:aws:s3:::BUCKET_NAME/*"
      ]
    }
  ]
}
```

Set up the trust policy for the EKS OIDC provider and annotate the ServiceAccount in `values.yaml`:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME"
```

## Installation

```bash
helm install cubejs charts/cubejs \
  -n cubejs \
  --set bigquery.projectId=my-gcp-project \
  --set cubestore.s3.bucket=my-cubestore-bucket \
  --set cubestore.s3.region=ap-southeast-1
```

Or with a custom values file:

```bash
helm install cubejs charts/cubejs -n cubejs -f my-values.yaml
```

## ARM64 / x86 nodes

CubeStore images default to ARM64 variants (`cubejs/cubestore:vX.Y.Z-arm64v8`) for use on AWS Graviton node groups.

For x86 nodes, override the image tags:

```yaml
cubestoreRouter:
  image: "cubejs/cubestore:v1.6.29"

cubestoreWorker:
  image: "cubejs/cubestore:v1.6.29"
```

## SQL API (Postgres protocol)

Cube's Postgres-compatible SQL API is **off by default** (REST and GraphQL work without it). Enable it to connect BI tools (Metabase, Superset, `psql`):

```yaml
cubeApi:
  sql:
    enabled: true
    port: 15432
```

When enabled, the chart sets `CUBEJS_PG_SQL_PORT` and exposes the port on the `cube-api` Service. The client credentials `CUBEJS_SQL_USER` and `CUBEJS_SQL_PASSWORD` are **arbitrary values you choose** — add both to the K8s Secret (`cubeApi.secret.name`) before enabling. They are independent of BigQuery authentication:

```bash
kubectl create secret generic cubejs-secret \
  --from-literal=CUBEJS_API_SECRET=$(openssl rand -hex 32) \
  --from-file=CUBEJS_DB_BQ_CREDENTIALS_FILE=sa-key.json \
  --from-literal=CUBEJS_SQL_USER=cube \
  --from-literal=CUBEJS_SQL_PASSWORD=$(openssl rand -hex 16) \
  -n cubejs
```

## Key values

| Value | Default | Description |
|-------|---------|-------------|
| `bigquery.projectId` | `""` (**required**) | GCP project ID for BigQuery |
| `cubestore.s3.bucket` | `""` (**required**) | S3 bucket for CubeStore remote storage |
| `cubestore.s3.region` | `ap-southeast-1` | AWS region of the S3 bucket |
| `cubestore.s3.subPath` | `""` | Optional key prefix within the bucket |
| `namespace` | `cubejs` | Kubernetes namespace (must be created manually) |
| `serviceAccount.name` | `cubejs-sa` | Name of the Kubernetes ServiceAccount |
| `serviceAccount.annotations` | `{}` | Use to set IRSA role ARN |
| `cubeApi.replicas` | `3` | Number of Cube API pods |
| `cubeRefreshWorker.replicas` | `1` | Number of refresh worker pods |
| `cubestoreRouter.replicas` | `1` | CubeStore router pods — do not exceed 1 |
| `cubestoreWorker.replicas` | `1` | Number of CubeStore worker pods |
| `cubeApi.secret.name` | `cubejs-secret` | Name of the K8s Secret with credentials |
| `cubeApi.sql.enabled` | `false` | Enable the Postgres-compatible SQL API |
| `cubeApi.sql.port` | `15432` | Port for the SQL API (set via `CUBEJS_PG_SQL_PORT`) |
