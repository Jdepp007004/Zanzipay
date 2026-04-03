#!/usr/bin/env bash
# Part 17: deploy, scripts, docs, frontend, and types fix
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── deploy/docker/ ───────────────────────────────────────────────────────────
cat > deploy/docker/Dockerfile << 'ENDOFFILE'
# syntax=docker/dockerfile:1
FROM golang:1.22-alpine AS builder
RUN apk add --no-cache git ca-certificates tzdata
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /out/zanzipay-server ./cmd/zanzipay-server/

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /out/zanzipay-server /zanzipay-server
EXPOSE 50053 8090 9090
ENTRYPOINT ["/zanzipay-server"]
ENDOFFILE
echo "  [OK] deploy/docker/Dockerfile"

cat > deploy/docker/Dockerfile.bench << 'ENDOFFILE'
FROM golang:1.22-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/zanzipay-bench ./cmd/zanzipay-bench/

FROM alpine:3.19
COPY --from=builder /out/zanzipay-bench /zanzipay-bench
ENTRYPOINT ["/zanzipay-bench"]
ENDOFFILE
echo "  [OK] deploy/docker/Dockerfile.bench"

cat > deploy/docker/Dockerfile.frontend << 'ENDOFFILE'
FROM node:20-alpine AS builder
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ .
RUN npm run build

FROM nginx:1.25-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
ENDOFFILE
echo "  [OK] deploy/docker/Dockerfile.frontend"

# ─── deploy/kubernetes/ ───────────────────────────────────────────────────────
cat > deploy/kubernetes/namespace.yaml << 'ENDOFFILE'
apiVersion: v1
kind: Namespace
metadata:
  name: zanzipay
  labels:
    name: zanzipay
ENDOFFILE
echo "  [OK] deploy/kubernetes/namespace.yaml"

cat > deploy/kubernetes/deployment.yaml << 'ENDOFFILE'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zanzipay
  namespace: zanzipay
spec:
  replicas: 3
  selector:
    matchLabels:
      app: zanzipay
  template:
    metadata:
      labels:
        app: zanzipay
    spec:
      containers:
        - name: zanzipay
          image: zanzipay/server:latest
          ports:
            - containerPort: 50053
              name: grpc
            - containerPort: 8090
              name: rest
            - containerPort: 9090
              name: metrics
          env:
            - name: ZANZIPAY_STORAGE_ENGINE
              value: postgres
            - name: ZANZIPAY_POSTGRES_DSN
              valueFrom:
                secretKeyRef:
                  name: zanzipay-secrets
                  key: postgres-dsn
            - name: ZANZIPAY_HMAC_KEY
              valueFrom:
                secretKeyRef:
                  name: zanzipay-secrets
                  key: hmac-key
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 2000m
              memory: 2Gi
          livenessProbe:
            httpGet:
              path: /v1/health
              port: rest
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /v1/health
              port: rest
            initialDelaySeconds: 3
            periodSeconds: 5
ENDOFFILE
echo "  [OK] deploy/kubernetes/deployment.yaml"

cat > deploy/kubernetes/service.yaml << 'ENDOFFILE'
apiVersion: v1
kind: Service
metadata:
  name: zanzipay
  namespace: zanzipay
spec:
  type: ClusterIP
  selector:
    app: zanzipay
  ports:
    - name: grpc
      port: 50053
      targetPort: grpc
    - name: rest
      port: 8090
      targetPort: rest
    - name: metrics
      port: 9090
      targetPort: metrics
ENDOFFILE
echo "  [OK] deploy/kubernetes/service.yaml"

cat > deploy/kubernetes/configmap.yaml << 'ENDOFFILE'
apiVersion: v1
kind: ConfigMap
metadata:
  name: zanzipay-config
  namespace: zanzipay
data:
  config.yaml: |
    server:
      grpc_port: 50053
      rest_port: 8090
    storage:
      engine: postgres
    rebac:
      cache_size: 100000
    audit:
      immutable: true
ENDOFFILE
echo "  [OK] deploy/kubernetes/configmap.yaml"

cat > deploy/kubernetes/hpa.yaml << 'ENDOFFILE'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: zanzipay
  namespace: zanzipay
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: zanzipay
  minReplicas: 3
  maxReplicas: 50
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
ENDOFFILE
echo "  [OK] deploy/kubernetes/hpa.yaml"

# ─── deploy/terraform/ ────────────────────────────────────────────────────────
cat > deploy/terraform/variables.tf << 'ENDOFFILE'
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}
variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}
variable "cluster_name" {
  description = "GKE Cluster name"
  type        = string
  default     = "zanzipay"
}
variable "node_count" {
  description = "Number of nodes per zone"
  type        = number
  default     = 3
}
ENDOFFILE
echo "  [OK] deploy/terraform/variables.tf"

cat > deploy/terraform/main.tf << 'ENDOFFILE'
terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}
provider "google" {
  project = var.project_id
  region  = var.region
}
resource "google_container_cluster" "zanzipay" {
  name     = var.cluster_name
  location = var.region
  initial_node_count = var.node_count
  node_config {
    machine_type = "n2-standard-4"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}
ENDOFFILE
echo "  [OK] deploy/terraform/main.tf"

cat > deploy/terraform/outputs.tf << 'ENDOFFILE'
output "cluster_endpoint" {
  value     = google_container_cluster.zanzipay.endpoint
  sensitive = true
}
output "cluster_name" {
  value = google_container_cluster.zanzipay.name
}
ENDOFFILE
echo "  [OK] deploy/terraform/outputs.tf"

# ─── scripts/ ─────────────────────────────────────────────────────────────────
cat > scripts/setup.sh << 'ENDOFFILE'
#!/usr/bin/env bash
# ZanziPay development environment setup
set -euo pipefail
echo "=== ZanziPay Development Setup ==="
GO_BIN=$HOME/go-install/go/bin
NODE_BIN=$HOME/node-install/bin

echo "--- Checking Go..."
$GO_BIN/go version

echo "--- Checking Node.js..."
$NODE_BIN/node --version
$NODE_BIN/npm --version

echo "--- Downloading Go modules..."
$GO_BIN/go mod download

echo "--- Installing frontend dependencies..."
cd frontend && $NODE_BIN/npm install; cd ..

echo "--- Building all binaries..."
$GO_BIN/go build -o bin/zanzipay-server ./cmd/zanzipay-server/
$GO_BIN/go build -o bin/zanzipay-cli    ./cmd/zanzipay-cli/
$GO_BIN/go build -o bin/zanzipay-bench  ./cmd/zanzipay-bench/

echo "=== Setup complete! ==="
echo "  Run: ./bin/zanzipay-server --config config.yaml"
ENDOFFILE
chmod +x scripts/setup.sh
echo "  [OK] scripts/setup.sh"

cat > scripts/generate-proto.sh << 'ENDOFFILE'
#!/usr/bin/env bash
# Generates Go code from proto files using buf
set -euo pipefail
if ! command -v buf &>/dev/null; then
    echo "Installing buf..."
    curl -sSL "https://github.com/bufbuild/buf/releases/download/v1.34.0/buf-Linux-x86_64" -o /usr/local/bin/buf
    chmod +x /usr/local/bin/buf
fi
cd api/proto
buf generate
echo "Proto generation complete."
ENDOFFILE
chmod +x scripts/generate-proto.sh
echo "  [OK] scripts/generate-proto.sh"

cat > scripts/run-benchmarks.sh << 'ENDOFFILE'
#!/usr/bin/env bash
# Full benchmark pipeline
set -euo pipefail
echo "=== ZanziPay Benchmark Pipeline ==="
BIN=$PWD/bin

echo "--- Starting competitor systems..."
docker compose -f docker-compose.bench.yml up -d
sleep 15

echo "--- Running benchmarks..."
$BIN/zanzipay-bench \
    --systems zanzipay,spicedb,openfga,cedar,keto \
    --scenarios all \
    --duration 30s \
    --concurrency 50 \
    --output bench/results/

echo "--- Analyzing results..."
cd bench/analysis
python3 analyze.py \
    --results-dir ../results/ \
    --output ../../frontend/src/data/results.json
cd ../..

echo "=== Benchmarks complete. Run: make bench-ui ==="
ENDOFFILE
chmod +x scripts/run-benchmarks.sh
echo "  [OK] scripts/run-benchmarks.sh"

cat > scripts/seed-data.sh << 'ENDOFFILE'
#!/usr/bin/env bash
# Seeds the development database with example data
set -euo pipefail
BIN=$PWD/bin
SERVER=localhost:50053

echo "=== Seeding ZanziPay with example Stripe schema data ==="

$BIN/zanzipay-cli --server $SERVER schema write < schemas/stripe/schema.zp
echo "  [OK] Schema loaded"

cat schemas/stripe/tuples.yaml | python3 -c "
import sys, yaml, json, subprocess
data = yaml.safe_load(sys.stdin)
for t in data.get('tuples', []):
    resource = f\"{t['resource_type']}:{t['resource_id']}\"
    relation = t['relation']
    subject_rel = '#' + t.get('subject_relation', '') if t.get('subject_relation') else ''
    subject = f\"{t['subject_type']}:{t['subject_id']}{subject_rel}\"
    print(f\"{resource}#{relation}@{subject}\")
" | while read tuple; do
    echo "  Writing: $tuple"
    $BIN/zanzipay-cli --server $SERVER tuple write "$tuple"
done

echo "=== Seed complete! ==="
ENDOFFILE
chmod +x scripts/seed-data.sh
echo "  [OK] scripts/seed-data.sh"

cat > scripts/generate-sanctions-list.sh << 'ENDOFFILE'
#!/usr/bin/env bash
# Downloads and formats the OFAC SDN list for use with ZanziPay
set -euo pipefail
mkdir -p /tmp/sanctions
echo "Downloading OFAC SDN List..."
curl -fsSL -o /tmp/sanctions/sdn.csv \
    "https://www.treasury.gov/ofac/downloads/sdn.csv" 2>/dev/null || \
    echo "Name,Country,Reason" > /tmp/sanctions/sdn.csv

echo "Processing..."
head -1000 /tmp/sanctions/sdn.csv > bench/analysis/sample_sanctions.csv
echo "Done: bench/analysis/sample_sanctions.csv"
ENDOFFILE
chmod +x scripts/generate-sanctions-list.sh
echo "  [OK] scripts/generate-sanctions-list.sh"

echo "=== deploy/ + scripts/ done ==="
ENDOFFILE
echo "Part 17 script written"
