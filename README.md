<div align="center">

# Velox

**Distributed Real-Time Inference Pipeline for High-Frequency Data Streams**

[![CI/CD](https://github.com/atharva-m/Velox/actions/workflows/ci.yml/badge.svg)](https://github.com/atharva-m/Velox/actions/workflows/ci.yml)
[![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![PyTorch](https://img.shields.io/badge/PyTorch-2.0+-ee4c2c.svg)](https://pytorch.org/)
[![Kafka](https://img.shields.io/badge/Apache%20Kafka-7.4.0-black.svg)](https://kafka.apache.org/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Ready-326CE5.svg)](https://kubernetes.io/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED.svg)](https://www.docker.com/)
[![Code Style: Black](https://img.shields.io/badge/code%20style-black-000000.svg)](https://github.com/psf/black)
[![Security: Trivy](https://img.shields.io/badge/security-trivy-blue)](https://github.com/aquasecurity/trivy)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[Overview](#overview) â€¢
[Performance](#performance) â€¢
[Architecture](#architecture) â€¢
[Quick Start](#quick-start) â€¢
[Kubernetes Deployment](#kubernetes-deployment) â€¢
[GPU Configuration](#gpu-configuration) â€¢
[Monitoring](#monitoring) â€¢
[Contributing](#contributing)

</div>

---

## Overview

This project implements a **production-ready, real-time image classification pipeline** using Apache Kafka for stream processing and PyTorch for GPU-accelerated inference. The system is designed to process high-throughput image streams with low latency, making it suitable for applications in computer vision, anomaly detection, and real-time monitoring systems.

### Key Features

- **High Throughput** â€” 1,683 images/sec with 8 GPU-accelerated pods
- **GPU Time-Slicing** â€” 8 pods share a single NVIDIA GPU efficiently
- **8.8x Scaling** â€” From 192 img/sec (single) to 1,683 img/sec (distributed)
- **Horizontal Pod Autoscaling** â€” Automatic scaling from 1-8 pods based on CPU utilization
- **High Accuracy** â€” 98.5% model confidence on shape classification
- **Observable** â€” Built-in Prometheus metrics and Grafana dashboards
- **Kubernetes Native** â€” Production-ready with auto-scaling and persistent storage
- **Containerized** â€” Fully Dockerized with health checks and dependency management

### Use Cases

- Real-time quality control in manufacturing
- Anomaly detection in video surveillance
- Automated content moderation
- Scientific image analysis pipelines

---

## Performance

### Benchmark Results

Tested on NVIDIA RTX 4070 with Minikube (8 CPUs, 20GB RAM):

| Metric | Single Process | Kubernetes (8 pods) | Improvement |
|--------|---------------|---------------------|-------------|
| **Throughput** | 192 img/sec | 1,683 img/sec | **8.8x** |
| **Per-Pod Throughput** | â€” | 210 img/sec | â€” |
| **Peak Throughput** | â€” | 1,949 img/sec | â€” |
| **Model Confidence** | 100% | 98.5% | â€” |

### Resource Utilization

| Resource | Per Pod | Total (8 pods) |
|----------|---------|----------------|
| **CPU** | ~950m | ~7.6 cores |
| **Memory** | ~1.5 GB | ~12 GB |
| **GPU** | 1/8 slice | 1 GPU (shared) |

### Scalability

```
Pods    Throughput      Per-Pod         Efficiency
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
1       ~210 img/sec    210 img/sec     100%
4       ~840 img/sec    210 img/sec     100%
8       ~1,683 img/sec  210 img/sec     100%
```

The system scales linearly with GPU time-slicing, maintaining consistent per-pod throughput as replicas increase.

---

## Architecture

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                         KAFKA ML INFERENCE PIPELINE                              â”‚
â”‚                           with GPU Time-Slicing                                  â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜

                                                    â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
                                                    â”‚      GPU (Time-Sliced)      â”‚
                                                    â”‚  â”Œâ”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”  â”‚
                                                    â”‚  â”‚ C1  â”‚ C2  â”‚ ... â”‚ C8  â”‚  â”‚
                                                    â”‚  â””â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”˜  â”‚
                                                    â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                                                                  â–²
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”      â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”      â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚              â”‚      â”‚              â”‚      â”‚       CONSUMER PODS (HPA: 1-8)       â”‚
â”‚  PRODUCER    â”‚ ---> â”‚    KAFKA     â”‚ ---> â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”     â”‚
â”‚    POD       â”‚      â”‚     POD      â”‚      â”‚  â”‚ Consumer 1 â”‚   â”‚ Consumer 2 â”‚ ... â”‚
â”‚              â”‚      â”‚              â”‚      â”‚  â”‚   (GPU)    â”‚   â”‚   (GPU)    â”‚     â”‚
â”‚  Synthetic   â”‚      â”‚  8 Partitionsâ”‚      â”‚  â””â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”˜     â”‚
â”‚  Image Gen   â”‚      â”‚  1,700+/sec  â”‚      â”‚        â”‚                â”‚            â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜      â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜      â””â”€â”€â”€â”€â”€â”€â”€â”€|â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€|â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                                                     â”‚                â”‚
                      â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”      â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
                      â”‚   GRAFANA    â”‚      â”‚            PROMETHEUS                â”‚
                      â”‚     POD      â”‚ <--- â”‚               POD                    â”‚
                      â”‚              â”‚      â”‚                                      â”‚
                      â”‚  Dashboards  â”‚      â”‚        Metrics (8 pods)              â”‚
                      â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜      â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
                                                     â”‚
                                            â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
                                            â”‚                  â”‚
                                            â”‚    MONGODB POD   â”‚
                                            â”‚   + PVC Storage  â”‚
                                            â”‚                  â”‚
                                            â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### Components

| Component | Description | Technology |
|-----------|-------------|------------|
| **Producer** | Generates synthetic shape images at 1,700+ msg/sec | Python, OpenCV |
| **Consumer** | GPU-accelerated inference, 210 img/sec per pod | PyTorch, CUDA |
| **Model Trainer** | One-time Kubernetes Job to train model on GPU | PyTorch |
| **Kafka** | Distributed message broker with 8 partitions | Apache Kafka |
| **MongoDB** | Document store for persisting detection results | MongoDB |
| **Prometheus** | Time-series metrics from all consumer pods | Prometheus |
| **Grafana** | Real-time monitoring dashboards | Grafana |

---

## Quick Start

### Option 1: Docker Compose (Development)

Best for local development and testing.

#### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (v20.10+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2.0+)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) (for GPU support)

#### Build and Start

```bash
git clone https://github.com/atharva-m/Velox.git
cd Velox

# Build the image
docker build -t ml-inference-app:latest .

# Start all services
docker-compose up -d
```

#### Verify Services

```bash
docker-compose ps
docker-compose logs -f consumer
```

You should see detections for all shape/color combinations:
```
MATCH: red_circle (Conf: 0.99)
MATCH: green_square (Conf: 0.98)
MATCH: red_square (Conf: 0.97)
MATCH: green_circle (Conf: 0.99)
```

---

### Option 2: Kubernetes (Production)

Best for production deployments with GPU time-slicing and auto-scaling.

See [Kubernetes Deployment](#kubernetes-deployment) section below.

---

## Kubernetes Deployment

Deploy the pipeline on Kubernetes with GPU time-slicing, Horizontal Pod Autoscaler, and automatic model training.

### Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) or any Kubernetes cluster
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- NVIDIA GPU with drivers installed
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

### Quick Deploy

Use the provided management script for one-command deployment:

**Windows (PowerShell):**
```powershell
# Start cluster with GPU time-slicing (8 pods sharing 1 GPU)
.\k8s.ps1 -Action start

# Start with custom resources
.\k8s.ps1 -Action start -CPUs 16 -Memory 32768 -Partitions 8

# Stop and cleanup
.\k8s.ps1 -Action stop
```

**Linux/macOS:**
```bash
./k8s.sh start
./k8s.sh stop
```

### What the Script Does

1. Starts Minikube with GPU passthrough (`--gpus all`)
2. Configures NVIDIA GPU time-slicing (8 replicas per GPU)
3. Enables metrics server for HPA
4. Builds the Docker image inside Minikube
5. Deploys infrastructure (Kafka, Zookeeper, MongoDB)
6. Creates Kafka topic with 8 partitions
7. Runs model training Job (one-time)
8. Deploys monitoring stack (Prometheus, Grafana)
9. Deploys consumer with HPA (auto-scales 1-8 pods)
10. Deploys producer

### Manual Deployment

```bash
# Start Minikube with GPU
minikube start --driver=docker --gpus all --cpus 8 --memory 20480

# Apply GPU time-slicing config
kubectl apply -f k8s-manifests/gpu-sharing-config.yaml
kubectl apply -f k8s-manifests/nvidia-device-plugin.yaml

# Verify 8 GPU slices are available
kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'
# Should output: 8

# Build image inside Minikube
minikube image build -t ml-inference-app:latest .

# Deploy all manifests
kubectl apply -f k8s-manifests/

# Create Kafka topic with 8 partitions
kubectl exec deployment/kafka -- kafka-topics.sh \
  --create --topic image_data \
  --partitions 8 --replication-factor 1 \
  --bootstrap-server localhost:29092

# Check status
kubectl get pods
kubectl get hpa
```

### Kubernetes Manifests

```
k8s-manifests/
â”œâ”€â”€ consumer-cm0-configmap.yaml           # Consumer binary data (model/app)
â”œâ”€â”€ consumer-deployment.yaml              # Consumer pods with GPU resources
â”œâ”€â”€ consumer-hpa.yaml                     # Horizontal Pod Autoscaler (1-8 replicas)
â”œâ”€â”€ consumer-service.yaml                 # Consumer service for Prometheus scraping
â”œâ”€â”€ discoveries-pvc.yaml                  # Shared PVC for model + detections
â”œâ”€â”€ env-configmap.yaml                    # Shared environment config
â”œâ”€â”€ gpu-sharing-config.yaml               # NVIDIA GPU time-slicing (8 replicas per GPU)
â”œâ”€â”€ nvidia-device-plugin.yaml             # NVIDIA device plugin DaemonSet
â”œâ”€â”€ grafana-deployment.yaml               # Grafana monitoring
â”œâ”€â”€ grafana-service.yaml
â”œâ”€â”€ kafka-deployment.yaml                 # Kafka broker
â”œâ”€â”€ kafka-service.yaml
â”œâ”€â”€ mongo-data-persistentvolumeclaim.yaml # MongoDB persistent storage
â”œâ”€â”€ mongo-deployment.yaml                 # MongoDB database
â”œâ”€â”€ mongo-service.yaml
â”œâ”€â”€ producer-cm0-configmap.yaml           # Producer binary data (app)
â”œâ”€â”€ producer-deployment.yaml              # Image producer
â”œâ”€â”€ prometheus-cm0-configmap.yaml         # Prometheus scrape config
â”œâ”€â”€ prometheus-deployment.yaml            # Metrics collection
â”œâ”€â”€ prometheus-service.yaml
â”œâ”€â”€ train-model.yaml                      # One-time model training Job
â”œâ”€â”€ zookeeper-deployment.yaml             # Kafka coordinator
â””â”€â”€ zookeeper-service.yaml
```

---

## GPU Configuration

### GPU Time-Slicing

This project uses NVIDIA GPU time-slicing to allow 8 consumer pods to share a single GPU, achieving **8.8x throughput scaling**.

```yaml
# gpu-sharing-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: kube-system
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 8    # Allow 8 pods to share 1 GPU
```

### How It Works

1. Single physical GPU is virtualized into 8 "slices"
2. Each consumer pod requests `nvidia.com/gpu: 1` (one slice)
3. Pods take turns using the GPU (time-multiplexed)
4. HPA scales consumers from 1-8 based on CPU utilization
5. Each pod achieves ~210 img/sec throughput

### Verify GPU Configuration

```bash
# Check GPU slices available on node
kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'
# Should output: 8

# Check GPU usage in pod
kubectl exec deployment/consumer -- nvidia-smi

# Check all consumer pods are using GPU
kubectl get pods -l io.kompose.service=consumer
```

### Horizontal Pod Autoscaler

The HPA automatically scales consumer pods based on CPU utilization:

```yaml
# consumer-hpa.yaml
spec:
  minReplicas: 1
  maxReplicas: 8
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
```

Monitor HPA:
```bash
kubectl get hpa consumer-hpa --watch
```

---

## Configuration

All configuration is managed through environment variables.

### Configuration Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `KAFKA_BOOTSTRAP_SERVER` | Kafka broker address | `kafka:29092` |
| `KAFKA_TOPIC` | Topic for image streaming | `image_data` |
| `KAFKA_CONSUMER_GROUP` | Consumer group ID | `gpu_rtx_4070` |
| `BATCH_SIZE` | Inference batch size | `8` |
| `QUEUE_SIZE` | Internal queue size | `200` |
| `METRICS_PORT` | Prometheus metrics port | `8000` |
| `MONGO_URI` | MongoDB connection string | `mongodb://mongo:27017/` |
| `DB_NAME` | Database name | `lab_discovery_db` |
| `STORAGE_PATH` | Path to save detected images | `./discoveries` |
| `MODEL_PATH` | Path to model weights | `model.pth` |
| `CLASSES_PATH` | Path to class labels | `classes.json` |
| `CONFIDENCE_THRESHOLD` | Minimum confidence for detection | `0.90` |
| `MAX_STORED_FILES` | Max images to keep in storage | `100` |

---

## Monitoring

### Prometheus Metrics

Access Prometheus:
- **Docker Compose:** [http://localhost:9090](http://localhost:9090)
- **Kubernetes:** `kubectl port-forward svc/prometheus 9090:9090`

Available metrics:
- `batch_avg_confidence` â€” Average model confidence per batch
- `target_shapes_found_total` â€” Counter of detected shapes (all classes)

### Grafana Dashboards

Access Grafana:
- **Docker Compose:** [http://localhost:3000](http://localhost:3000)
- **Kubernetes:** `kubectl port-forward svc/grafana 3000:3000`

Default credentials: `admin` / `admin`

#### Example Queries

```promql
# Aggregate throughput (all pods)
sum(rate(target_shapes_found_total[1m]))

# Average Confidence
avg(batch_avg_confidence)

# Detection Rate by Pod
sum by (pod) (rate(target_shapes_found_total[1m]))
```

### MongoDB Queries

Query detections in MongoDB Compass:

```javascript
// Latest detections
db.shapes_found.find().sort({timestamp: -1}).limit(10)

// Count by label
db.shapes_found.aggregate([
  {$group: {_id: "$predicted_label", count: {$sum: 1}}}
])

// High confidence detections
db.shapes_found.find({confidence: {$gt: 0.95}})
```

---

## CI/CD

This project uses **GitHub Actions** for continuous integration and delivery.

### Pipeline Overview

| Job | Description |
|-----|-------------|
| **Lint & Validate** | Runs flake8 linting and validates docker-compose configuration |
| **Build Image** | Builds Docker image and pushes to GitHub Container Registry |
| **Integration Tests** | Starts infrastructure services and tests connectivity |
| **Security Scan** | Scans for vulnerabilities using Trivy |
| **Release Info** | Generates release summary on successful builds |

### Using Pre-built Images

```bash
docker pull ghcr.io/atharva-m/Velox:latest
```

---

## Project Structure

```
Velox/
â”œâ”€â”€ .github/
â”‚   â””â”€â”€ workflows/
â”‚       â””â”€â”€ ci.yml               # CI/CD pipeline
â”œâ”€â”€ k8s-manifests/               # Kubernetes manifests
â”‚   â”œâ”€â”€ consumer-deployment.yaml
â”‚   â”œâ”€â”€ consumer-hpa.yaml        # Horizontal Pod Autoscaler
â”‚   â”œâ”€â”€ gpu-sharing-config.yaml  # GPU time-slicing config
â”‚   â”œâ”€â”€ nvidia-device-plugin.yaml# NVIDIA device plugin
â”‚   â”œâ”€â”€ train-model.yaml         # Model training Job
â”‚   â””â”€â”€ ...
â”œâ”€â”€ consumer.py                  # ML inference consumer
â”œâ”€â”€ producer.py                  # Synthetic image generator
â”œâ”€â”€ train.py                     # Model training script
â”œâ”€â”€ start.sh                     # Container entrypoint
â”œâ”€â”€ k8s.sh                       # Kubernetes management (Linux/macOS)
â”œâ”€â”€ k8s.ps1                      # Kubernetes management (Windows)
â”œâ”€â”€ docker-compose.yml           # Docker Compose orchestration
â”œâ”€â”€ Dockerfile                   # Container image definition
â”œâ”€â”€ prometheus.yml               # Prometheus configuration
â”œâ”€â”€ requirements.txt             # Python dependencies
â”œâ”€â”€ .env                         # Environment configuration
â””â”€â”€ discoveries/                 # Saved detection images
```

---

## Performance Tuning

### High Throughput (Kubernetes)

```bash
# Ensure 8 Kafka partitions for parallel processing
kubectl exec deployment/kafka -- kafka-topics.sh \
  --alter --topic image_data --partitions 8 \
  --bootstrap-server localhost:29092

# Scale to 8 consumers (or let HPA auto-scale)
kubectl scale deployment consumer --replicas=8

# Verify throughput via Prometheus
# sum(rate(target_shapes_found_total[1m])) should show ~1,700/sec
```

### Managing Kafka Backlog

```bash
# Check consumer lag
kubectl exec deployment/kafka -- kafka-consumer-groups.sh \
  --describe --group gpu_rtx_4070 \
  --bootstrap-server localhost:29092

# Reset offsets to latest (skip backlog)
kubectl scale deployment consumer --replicas=0
kubectl exec deployment/kafka -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:29092 \
  --group gpu_rtx_4070 \
  --reset-offsets --to-latest \
  --topic image_data --execute
kubectl scale deployment consumer --replicas=8
```

---

## Troubleshooting

### Kubernetes Issues

**Pods stuck in Pending (GPU):**
```bash
# Check if GPU slices are available
kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'

# Check device plugin is running
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Check device plugin logs
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds
```

**Model not found:**
```bash
# Check if training Job completed
kubectl get jobs
kubectl logs job/model-trainer

# Re-run training
kubectl delete job model-trainer
kubectl apply -f k8s-manifests/train-model.yaml
```

**Consumer not receiving messages:**
```bash
# Check Kafka topic
kubectl exec deployment/kafka -- kafka-topics.sh \
  --describe --topic image_data \
  --bootstrap-server localhost:29092

# Check consumer group lag
kubectl exec deployment/kafka -- kafka-consumer-groups.sh \
  --describe --group gpu_rtx_4070 \
  --bootstrap-server localhost:29092
```

**HPA not scaling:**
```bash
# Enable metrics server
minikube addons disable metrics-server
minikube addons enable metrics-server

# Check HPA status
kubectl describe hpa consumer-hpa
```

### Docker Compose Issues

**Kafka connection refused:**
```bash
docker-compose ps kafka
docker-compose logs kafka
```

**CUDA not available:**
```bash
# Verify GPU access
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the Veloxsitory
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Quality

```bash
# Run linter
flake8 . --count --max-line-length=120 --extend-ignore=E203 --statistics

# Validate configurations
docker compose config -q
kubectl apply --dry-run=client -f k8s-manifests/
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Built with â¤ï¸ using PyTorch, Kafka, Kubernetes, and Docker**

[Veloxrt Bug](https://github.com/atharva-m/Velox/issues) â€¢
[Request Feature](https://github.com/atharva-m/Velox/issues)

</div>