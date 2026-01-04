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

[Overview](#overview) •
[Architecture](#architecture) •
[Quick Start](#quick-start) •
[Kubernetes Deployment](#kubernetes-deployment) •
[GPU Configuration](#gpu-configuration) •
[Configuration](#configuration) •
[Monitoring](#monitoring) •
[CI/CD](#cicd) •
[Contributing](#contributing)

</div>

---

## Overview

This project implements a **production-ready, real-time image classification pipeline** using Apache Kafka for stream processing and PyTorch for GPU-accelerated inference. The system is designed to process high-throughput image streams with low latency, making it suitable for applications in computer vision, anomaly detection, and real-time monitoring systems.

### Key Features

- **Real-Time Processing** — Sub-second inference on streaming images via Kafka
- **GPU-Accelerated** — Batched inference using PyTorch with CUDA support
- **GPU Time-Slicing** — Multiple consumer pods share a single GPU efficiently
- **Horizontal Pod Autoscaling** — Automatic scaling based on CPU utilization
- **Kubernetes Native** — Production-ready with auto-scaling consumers and persistent storage
- **Observable** — Built-in Prometheus metrics and Grafana dashboards
- **Containerized** — Fully Dockerized with health checks and dependency management
- **Configurable** — Environment-based configuration for all components
- **Persistent Storage** — MongoDB integration for storing detection results
- **CI/CD Ready** — Automated testing, linting, and Docker image builds

### Use Cases

- Real-time quality control in manufacturing
- Anomaly detection in video surveillance
- Automated content moderation
- Scientific image analysis pipelines

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                         KAFKA ML INFERENCE PIPELINE                              │
│                           with GPU Time-Slicing                                  │
└──────────────────────────────────────────────────────────────────────────────────┘

                                                    ┌─────────────────────────────┐
                                                    │      GPU (Time-Sliced)      │
                                                    │  ┌─────┬─────┬─────┬─────┐  │
                                                    │  │ C1  │ C2  │ ... │ C8  │  │
                                                    │  └─────┴─────┴─────┴─────┘  │
                                                    └─────────────────────────────┘
                                                                  ▲
┌──────────────┐      ┌──────────────┐      ┌──────────────────────────────────────┐
│              │      │              │      │       CONSUMER PODS (HPA: 1-8)       │
│  PRODUCER    │ ---> │    KAFKA     │ ---> │  ┌────────────┐   ┌────────────┐     │
│    POD       │      │     POD      │      │  │ Consumer 1 │   │ Consumer 2 │ ... │
│              │      │              │      │  │   (GPU)    │   │   (GPU)    │     │
│  Synthetic   │      │  Partitioned │      │  └─────┬──────┘   └─────┬──────┘     │
│  Image Gen   │      │    Topic     │      │        │                │            │
└──────────────┘      └──────────────┘      └────────|────────────────|────────────┘
                                                     │                │
                      ┌──────────────┐      ┌────────▼────────────────▼────────────┐
                      │   GRAFANA    │      │            PROMETHEUS                │
                      │     POD      │ <--- │               POD                    │
                      │              │      │                                      │
                      │  Dashboards  │      │             Metrics                  │
                      └──────────────┘      └──────────────────────────────────────┘
                                                     │
                                            ┌────────▼─────────┐
                                            │                  │
                                            │    MONGODB POD   │
                                            │   + PVC Storage  │
                                            │                  │
                                            └──────────────────┘
```

### Components

| Component | Description | Technology |
|-----------|-------------|------------|
| **Producer** | Generates synthetic shape images and streams them to Kafka | Python, OpenCV |
| **Consumer** | GPU-accelerated inference with auto-scaling (1-8 replicas) | PyTorch, CUDA |
| **Model Trainer** | One-time Kubernetes Job to train model on GPU | PyTorch |
| **Kafka** | Distributed message broker with partitioned topics | Apache Kafka |
| **MongoDB** | Document store for persisting detection results | MongoDB |
| **Prometheus** | Time-series metrics collection | Prometheus |
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
# Start cluster (GPU-enabled by default)
.\k8s.ps1 -Action start

# Start with custom Kafka partitions
.\k8s.ps1 -Action start -Partitions 5

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
2. Enables NVIDIA device plugin for Kubernetes
3. Builds the Docker image inside Minikube
4. Deploys infrastructure (Kafka, Zookeeper, MongoDB)
5. Deploys monitoring stack (Prometheus, Grafana)
6. Creates Kafka topic with specified partitions
7. Runs model training Job (one-time)
8. Deploys consumer with HPA (auto-scales 1-8 pods)
9. Deploys producer

### Manual Deployment

```bash
# Start Minikube with GPU
minikube start --driver=docker --gpus all
minikube addons enable nvidia-device-plugin

# Build image inside Minikube
minikube image build -t ml-inference-app:latest .

# Apply GPU time-slicing config (optional, for multi-pod GPU sharing)
kubectl apply -f k8s-manifests/gpu-sharing-config.yaml

# Deploy all manifests
kubectl apply -f k8s-manifests/

# Run model training Job
kubectl apply -f k8s-manifests/train-model.yaml

# Wait for training to complete
kubectl wait --for=condition=complete job/model-trainer --timeout=300s

# Create Kafka topic
kubectl exec deployment/kafka -- kafka-topics.sh \
  --create --topic image_data \
  --partitions 3 --replication-factor 1 \
  --bootstrap-server localhost:29092

# Check status
kubectl get pods
kubectl get hpa
```

### Kubernetes Manifests

```
k8s-manifests/
├── consumer-cm0-configmap.yaml           # Consumer binary data (model/app)
├── consumer-deployment.yaml              # Consumer pods with GPU resources
├── consumer-hpa.yaml                     # Horizontal Pod Autoscaler (1-8 replicas)
├── consumer-service.yaml                 # Consumer service for Prometheus scraping
├── discoveries-pvc.yaml                  # Shared PVC for model + detections
├── env-configmap.yaml                    # Shared environment config
├── gpu-sharing-config.yaml               # NVIDIA GPU time-slicing (8 replicas per GPU)
├── grafana-deployment.yaml               # Grafana monitoring
├── grafana-service.yaml
├── kafka-deployment.yaml                 # Kafka broker
├── kafka-service.yaml
├── mongo-data-persistentvolumeclaim.yaml # MongoDB persistent storage
├── mongo-deployment.yaml                 # MongoDB database
├── mongo-service.yaml
├── producer-cm0-configmap.yaml           # Producer binary data (app)
├── producer-deployment.yaml              # Image producer
├── prometheus-cm0-configmap.yaml         # Prometheus scrape config
├── prometheus-deployment.yaml            # Metrics collection
├── prometheus-service.yaml
├── train-model.yaml                      # One-time model training Job
├── zookeeper-deployment.yaml             # Kafka coordinator
└── zookeeper-service.yaml
```

---

## GPU Configuration

### GPU Time-Slicing

This project uses NVIDIA GPU time-slicing to allow multiple consumer pods to share a single GPU. This is configured in `gpu-sharing-config.yaml`:

```yaml
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
4. HPA can scale consumers from 1 to 8 based on CPU usage

### Verify GPU Availability

```bash
# Check GPU resources on node
kubectl describe node | grep -A 10 "Allocated resources"

# Should show: nvidia.com/gpu: 8 (with time-slicing)

# Check GPU usage in pod
kubectl exec deployment/consumer -- nvidia-smi
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
        averageUtilization: 50
```

Monitor HPA:
```bash
kubectl get hpa consumer-hpa --watch
```

---

## Configuration

All configuration is managed through environment variables.

### Docker Compose

Configure via `.env` file.

### Kubernetes

Configure via ConfigMaps:

```yaml
# consumer-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: consumer-env
data:
  KAFKA_BOOTSTRAP_SERVER: "kafka:29092"
  MONGO_URI: "mongodb://mongo:27017/"
  BATCH_SIZE: "8"
  CONFIDENCE_THRESHOLD: "0.90"
  MAX_STORED_FILES: "100"
```

### Configuration Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `KAFKA_BOOTSTRAP_SERVER` | Kafka broker address | `kafka:29092` |
| `KAFKA_TOPIC` | Topic for image streaming | `image_data` |
| `KAFKA_CONSUMER_GROUP` | Consumer group ID | `gpu_cluster_h100` |
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
- `batch_avg_confidence` — Average model confidence per batch
- `target_shapes_found` — Counter of detected shapes (all classes)

### Grafana Dashboards

Access Grafana:
- **Docker Compose:** [http://localhost:3000](http://localhost:3000)
- **Kubernetes:** `kubectl port-forward svc/grafana 3000:3000`

Default credentials: `admin` / `admin`

#### Example Queries

```promql
# Average Confidence Over Time
batch_avg_confidence

# Detection Rate (per minute)
rate(target_shapes_found[1m]) * 60

# Detections by Consumer Pod
sum by (pod) (target_shapes_found)
```

### MongoDB Queries

Query detections in MongoDB Compass:

```json
// Latest green_square detection
{"predicted_label": "green_square"}
// Sort: {"timestamp": -1}, Limit: 1

// All detections with new timestamp format
{"timestamp": {"$type": "string"}}

// Count by label
// Use Aggregation: [{"$group": {"_id": "$predicted_label", "count": {"$sum": 1}}}]
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
velox/
├── .github/
│   └── workflows/
│       └── ci.yml               # CI/CD pipeline
├── k8s-manifests/               # Kubernetes manifests
│   ├── consumer-deployment.yaml
│   ├── consumer-hpa.yaml        # Horizontal Pod Autoscaler
│   ├── gpu-sharing-config.yaml  # GPU time-slicing config
│   ├── train-model.yaml         # Model training Job
│   └── ...
├── consumer.py                  # ML inference consumer
├── producer.py                  # Synthetic image generator
├── train.py                     # Model training script
├── start.sh                     # Container entrypoint
├── k8s.sh                       # Kubernetes management (Linux/macOS)
├── k8s.ps1                      # Kubernetes management (Windows)
├── docker-compose.yml           # Docker Compose orchestration
├── Dockerfile                   # Container image definition
├── prometheus.yml               # Prometheus configuration
├── requirements.txt             # Python dependencies
├── .env                         # Environment configuration
└── discoveries/                 # Saved detection images
```

---

## Performance Tuning

### High Throughput (Kubernetes)

```bash
# Increase Kafka partitions
kubectl exec deployment/kafka -- kafka-topics.sh \
  --alter --topic image_data --partitions 8 \
  --bootstrap-server localhost:29092

# HPA will auto-scale consumers up to 8
# Or manually scale:
kubectl scale deployment consumer --replicas=8
```

### High Throughput (Docker)

```env
BATCH_SIZE=32           # Larger batches for GPU efficiency
QUEUE_SIZE=500          # Larger buffer for burst handling
PRODUCER_INTERVAL=0.01  # Faster image generation
```

### Low Latency

```env
BATCH_SIZE=1            # Process immediately
QUEUE_SIZE=50           # Smaller buffer
```

---

## Troubleshooting

### Kubernetes Issues

**Pods stuck in Pending (GPU):**
```bash
# Check if GPU is available
kubectl describe node | grep nvidia.com/gpu

# Check device plugin
kubectl get pods -n kube-system | grep nvidia

# Verify GPU time-slicing
kubectl get configmap -n kube-system time-slicing-config -o yaml
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

# Check consumer group
kubectl exec deployment/kafka -- kafka-consumer-groups.sh \
  --describe --group gpu_cluster_h100 \
  --bootstrap-server localhost:29092
```

**HPA not scaling:**
```bash
# Check metrics server
kubectl get deployment metrics-server -n kube-system

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

1. Fork the repository
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

**Built with ❤️ using PyTorch, Kafka, Kubernetes, and Docker**

[Report Bug](https://github.com/atharva-m/Velox/issues) •
[Request Feature](https://github.com/atharva-m/Velox/issues)

</div>