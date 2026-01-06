#!/bin/bash

# Parameters
ACTION=$1
PARTITIONS=${2:-8}
CPUS=${3:-8}
MEMORY=${4:-20480}

if [ -z "$ACTION" ]; then
  echo "Usage: ./k8s.sh [start|stop] [partitions] [cpus] [memory]"
  exit 1
fi

# Colors for formatting
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
GRAY='\033[0;37m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$ACTION" == "stop" ]; then
    echo -e "${YELLOW}Shutting down the cluster${NC}"
    kubectl scale deployment consumer --replicas=0 2>/dev/null

    kubectl delete deployment producer consumer kafka zookeeper mongo prometheus grafana --ignore-not-found
    kubectl delete job model-trainer --ignore-not-found
    kubectl delete service kafka zookeeper mongo prometheus grafana consumer --ignore-not-found
    kubectl delete configmap prometheus-cm0 consumer-env --ignore-not-found
    kubectl delete hpa consumer-hpa --ignore-not-found
    kubectl delete pvc discoveries-pvc --ignore-not-found
    minikube stop
    echo -e "${GREEN}Shutdown Complete${NC}"
fi

if [ "$ACTION" == "start" ]; then
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Starting Kubernetes GPU Cluster${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GRAY}CPUs: $CPUs | Memory: $MEMORY MB | Partitions: $PARTITIONS${NC}\n"

    # Start Minikube with GPU and resources
    echo -e "${CYAN}[1/10] Starting Minikube with GPU${NC}"
    minikube start --driver=docker --gpus all --cpus "$CPUs" --memory "$MEMORY"
    minikube addons enable metrics-server

    # Configure GPU Time-Slicing
    echo -e "${CYAN}[2/10] Configuring GPU Time-Slicing${NC}"
    kubectl apply -f k8s-manifests/gpu-sharing-config.yaml
    kubectl apply -f k8s-manifests/nvidia-device-plugin.yaml
    
    # Restart device plugin pod to pick up new config
    kubectl rollout restart daemonset nvidia-device-plugin-daemonset -n kube-system
    sleep 5
    kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n kube-system --timeout=60s

    # Wait for GPU slices
    echo -e "${YELLOW}Waiting for GPU time-slicing to activate${NC}"
    gpuCount=0
    attempts=0
    while [ "$gpuCount" -lt 8 ] && [ "$attempts" -lt 30 ]; do
        sleep 2
        # Parse JSON to find the allocatable GPU count
        gpuCount=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[0].status.allocatable."nvidia.com/gpu"')
        # Handle null cases if jq fails or node is not ready
        if [ "$gpuCount" == "null" ] || [ -z "$gpuCount" ]; then gpuCount=0; fi
        attempts=$((attempts + 1))
        echo -n "."
    done
    echo -e ""

    if [ "$gpuCount" -ge 8 ]; then
        echo -e "${GREEN}GPU Time-Slicing active: $gpuCount GPU slices available${NC}"
    else
        echo -e "${YELLOW}Warning: GPU count is $gpuCount (expected 8). Continuing...${NC}"
    fi

    # Build Docker Image
    echo -e "${CYAN}[3/10] Building Docker Image${NC}"
    if minikube image build -t ml-inference-app:latest . ; then
        echo -e "${GREEN}Image built successfully${NC}"
    else
        echo -e "${RED}Image build failed!${NC}"
        exit 1
    fi

    # Deploy Storage and Config
    echo -e "${CYAN}[4/10] Deploying Storage and Config${NC}"
    kubectl apply -f k8s-manifests/discoveries-pvc.yaml
    kubectl create configmap consumer-env --from-env-file=.env --dry-run=client -o yaml | kubectl apply -f -

    # Deploy Infrastructure Services
    echo -e "${CYAN}[5/10] Deploying Infrastructure (Mongo, Zookeeper, Kafka)${NC}"
    kubectl apply -f k8s-manifests/mongo-service.yaml
    kubectl apply -f k8s-manifests/zookeeper-service.yaml
    kubectl apply -f k8s-manifests/kafka-service.yaml
    kubectl apply -f k8s-manifests/mongo-deployment.yaml
    kubectl apply -f k8s-manifests/zookeeper-deployment.yaml
    kubectl apply -f k8s-manifests/kafka-deployment.yaml

    # Wait for Kafka
    echo -e "${YELLOW}Waiting for Kafka to be ready${NC}"
    while [[ $(kubectl get pod -l io.kompose.service=kafka -o jsonpath='{.items[0].status.phase}' 2>/dev/null) != "Running" ]]; do
        echo -n "."
        sleep 3
    done
    echo -e "\n${GREEN}Kafka is online${NC}"

    sleep 10

    # Create Kafka Topic
    echo -e "${CYAN}[6/10] Creating Kafka Topic ($PARTITIONS partitions)${NC}"
    topicCreated=false
    topicAttempts=0
    while [ "$topicCreated" = false ] && [ "$topicAttempts" -lt 10 ]; do
        if kubectl exec deployment/kafka -- kafka-topics.sh --create --topic image_data --partitions "$PARTITIONS" --replication-factor 1 --bootstrap-server localhost:29092 --if-not-exists 2>/dev/null; then
            topicCreated=true
        else
            topicAttempts=$((topicAttempts + 1))
            echo -e "${GRAY}Retrying topic creation...${NC}"
            sleep 3
        fi
    done

    if [ "$topicCreated" = true ]; then
        echo -e "${GREEN}Topic 'image_data' created ($PARTITIONS partitions)${NC}"
    else
        echo -e "${YELLOW}Warning: Topic creation may have failed${NC}"
    fi

    # Train Model
    echo -e "${CYAN}[7/10] Training ML Model${NC}"
    kubectl apply -f k8s-manifests/train-model.yaml

    echo -e "${YELLOW}Waiting for training to start${NC}"
    trainingStarted=false
    while [ "$trainingStarted" = false ]; do
        podStatus=$(kubectl get pod -l job-name=model-trainer -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        if [[ "$podStatus" == "Running" || "$podStatus" == "Succeeded" ]]; then
            trainingStarted=true
        fi
        sleep 2
    done

    kubectl logs -f job/model-trainer --timestamps
    kubectl wait --for=condition=complete --timeout=600s job/model-trainer
    echo -e "${GREEN}Training complete${NC}"

    # Deploy Monitoring
    echo -e "${CYAN}[8/10] Deploying Monitoring (Prometheus, Grafana)${NC}"
    kubectl apply -f k8s-manifests/prometheus-cm0-configmap.yaml
    kubectl apply -f k8s-manifests/prometheus-service.yaml
    kubectl apply -f k8s-manifests/grafana-service.yaml
    kubectl apply -f k8s-manifests/prometheus-deployment.yaml
    kubectl apply -f k8s-manifests/grafana-deployment.yaml

    # Deploy Consumer
    echo -e "${CYAN}[9/10] Deploying Consumer with HPA${NC}"
    kubectl apply -f k8s-manifests/consumer-service.yaml
    kubectl apply -f k8s-manifests/consumer-deployment.yaml
    kubectl apply -f k8s-manifests/consumer-hpa.yaml
    minikube addons disable metrics-server 2>/dev/null
    minikube addons enable metrics-server
    sleep 5

    # Deploy Producer
    echo -e "${CYAN}[10/10] Deploying Producer${NC}"
    kubectl apply -f k8s-manifests/producer-deployment.yaml

    # Wait for pods to stabilize
    echo -e "${YELLOW}Waiting for pods to be ready${NC}"
    sleep 10

    # Final Status
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}        SYSTEM ONLINE${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    echo -e "${CYAN}Configuration:${NC}"
    echo -e "  GPU Slices:       $gpuCount"
    echo -e "  Kafka Partitions: $PARTITIONS"
    echo -e "  HPA Range:        1-8 pods\n"
    echo -e "${YELLOW}Access Dashboards:${NC}"
    echo -e "  kubectl port-forward svc/grafana 3000:3000"
    echo -e "  kubectl port-forward svc/prometheus 9090:9090"
    echo -e "  kubectl port-forward svc/mongo 27017:27017\n"

    kubectl get pods
fi