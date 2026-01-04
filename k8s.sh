#!/bin/bash

ACTION=$1
PARTITIONS=${2:-8}

if [ -z "$ACTION" ]; then
  echo "Usage: ./k8s.sh [start|stop] [partitions (default: 8)]"
  exit 1
fi

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
    kubectl delete configmap prometheus-cm0 consumer-env gpu-sharing-config --ignore-not-found
    kubectl delete hpa consumer-hpa --ignore-not-found
    kubectl delete pvc discoveries-pvc --ignore-not-found
    minikube stop
    echo -e "${GREEN}Shutdown Complete${NC}"
fi

if [ "$ACTION" == "start" ]; then
    echo -e "${CYAN}Starting Minikube${NC}"
    minikube start --driver=docker --gpus all
    
    echo -e "${CYAN}Enabling addons${NC}"
    minikube addons enable nvidia-device-plugin
    minikube addons enable metrics-server
    
    echo -e "${YELLOW}Refreshing Metrics Server${NC}"
    kubectl delete pod -n kube-system -l k8s-app=metrics-server --ignore-not-found
    
    echo -e "${CYAN}Configuring GPU Time-Slicing${NC}"
    kubectl apply -f k8s-manifests/gpu-sharing-config.yaml
    kubectl patch daemonset nvidia-device-plugin-daemonset -n kube-system --patch '{"spec":{"template":{"spec":{"containers":[{"name":"nvidia-device-plugin-ctr","volumeMounts":[{"name":"config","mountPath":"/etc/nvidia-device-plugin"}]}],"volumes":[{"name":"config","configMap":{"name":"time-slicing-config"}}]}}}}'
    kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds
    
    sleep 10

    echo -e "${CYAN}Building Docker Image inside Minikube${NC}"
    if minikube image build -t ml-inference-app:latest . ; then
        echo -e "${GREEN}Image built successfully${NC}"
    else
        echo -e "${RED}Image build failed!${NC}"
        exit 1
    fi

    echo -e "${CYAN}Deploying Infrastructure${NC}"
    kubectl apply -f k8s-manifests/discoveries-pvc.yaml
    kubectl create configmap consumer-env --from-env-file=.env --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply -f k8s-manifests/mongo-service.yaml
    kubectl apply -f k8s-manifests/zookeeper-service.yaml
    kubectl apply -f k8s-manifests/kafka-service.yaml
    
    kubectl apply -f k8s-manifests/mongo-deployment.yaml
    kubectl apply -f k8s-manifests/zookeeper-deployment.yaml
    kubectl apply -f k8s-manifests/kafka-deployment.yaml

    echo -e "${YELLOW}Waiting for Kafka to be Ready${NC}"
    while [[ $(kubectl get pod -l io.kompose.service=kafka -o jsonpath='{.items[0].status.phase}' 2>/dev/null) != "Running" ]]; do
        echo -n "."
        sleep 3
    done
    echo -e "\n${GREEN}Kafka is online${NC}"
    
    sleep 10

    echo -e "${CYAN}Initializing Topic with $PARTITIONS Partitions${NC}"
    topicCreated=false
    while [ "$topicCreated" = false ]; do
        if kubectl exec deployment/kafka -- kafka-topics.sh --create --topic image_data --partitions "$PARTITIONS" --replication-factor 1 --bootstrap-server localhost:29092 --if-not-exists > /dev/null 2>&1; then
            topicCreated=true
        else
            echo -e "${GRAY}Waiting for Kafka API${NC}"
            sleep 2
        fi
    done
    echo -e "${GREEN}Topic 'image_data' verified ($PARTITIONS Partitions)${NC}"

    echo -e "${YELLOW}Launching Training job${NC}"
    kubectl apply -f k8s-manifests/train-model.yaml

    podStatus=""
    while [[ "$podStatus" != "Running" && "$podStatus" != "Succeeded" ]]; do
        podStatus=$(kubectl get pod -l job-name=model-trainer -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        sleep 2
    done
    
    kubectl logs -f job/model-trainer --timestamps
    kubectl wait --for=condition=complete --timeout=600s job/model-trainer
    echo -e "${GREEN}Training complete${NC}"

    echo -e "${CYAN}Deploying Monitoring Stack${NC}"
    kubectl apply -f k8s-manifests/prometheus-cm0-configmap.yaml
    kubectl apply -f k8s-manifests/prometheus-service.yaml
    kubectl apply -f k8s-manifests/grafana-service.yaml
    kubectl apply -f k8s-manifests/prometheus-deployment.yaml
    kubectl apply -f k8s-manifests/grafana-deployment.yaml

    echo -e "${CYAN}Deploying Apps${NC}"
    kubectl apply -f k8s-manifests/consumer-service.yaml
    kubectl apply -f k8s-manifests/consumer-deployment.yaml
    
    kubectl apply -f k8s-manifests/consumer-hpa.yaml
    echo -e "${GREEN}Horizontal Pod Autoscaler enabled${NC}"
    
    kubectl apply -f k8s-manifests/producer-deployment.yaml

    echo -e "${GREEN}SYSTEM ONLINE${NC}"
    echo -e "${YELLOW}To access dashboards and storage, run in separate terminals:${NC}"
    echo -e "  kubectl port-forward svc/grafana 3000:3000"
    echo -e "  kubectl port-forward svc/prometheus 9090:9090"
    echo -e "  kubectl port-forward service/mongo 27017:27017"
    
    kubectl get pods
fi