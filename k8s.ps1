param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [int]$Partitions = 8
)

if ($Action -eq "stop") {
    Write-Host "Shutting down the cluster" -ForegroundColor Yellow
    kubectl scale deployment consumer --replicas=0 2>$null

    kubectl delete deployment producer consumer kafka zookeeper mongo prometheus grafana --ignore-not-found
    kubectl delete job model-trainer --ignore-not-found
    kubectl delete service kafka zookeeper mongo prometheus grafana consumer --ignore-not-found
    kubectl delete configmap prometheus-cm0 consumer-env gpu-sharing-config --ignore-not-found
    kubectl delete hpa consumer-hpa --ignore-not-found
    kubectl delete pvc discoveries-pvc --ignore-not-found
    minikube stop
    Write-Host "Shutdown Complete" -ForegroundColor Green
}

if ($Action -eq "start") {
    Write-Host "Starting Minikube" -ForegroundColor Cyan
    minikube start --driver=docker --gpus all
    
    Write-Host "Enabling addons" -ForegroundColor Cyan
    minikube addons enable nvidia-device-plugin
    minikube addons enable metrics-server
    
    Write-Host "Refreshing Metrics Server" -ForegroundColor Yellow
    kubectl delete pod -n kube-system -l k8s-app=metrics-server --ignore-not-found
    
    Write-Host "Configuring GPU Time-Slicing" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/gpu-sharing-config.yaml
    kubectl patch daemonset nvidia-device-plugin-daemonset -n kube-system --patch '{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"nvidia-device-plugin-ctr\",\"volumeMounts\":[{\"name\":\"config\",\"mountPath\":\"/etc/nvidia-device-plugin\"}]}],\"volumes\":[{\"name\":\"config\",\"configMap\":{\"name\":\"time-slicing-config\"}}]}}}}'
    kubectl delete pod -n kube-system -l name=nvidia-device-plugin-ds
    
    Start-Sleep -Seconds 10

    Write-Host "Building Docker Image inside Minikube" -ForegroundColor Cyan
    minikube image build -t ml-inference-app:latest .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Image build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Image built successfully" -ForegroundColor Green

    Write-Host "Deploying Infrastructure" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/discoveries-pvc.yaml
    kubectl create configmap consumer-env --from-env-file=.env --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply -f k8s-manifests/mongo-service.yaml
    kubectl apply -f k8s-manifests/zookeeper-service.yaml
    kubectl apply -f k8s-manifests/kafka-service.yaml
    
    kubectl apply -f k8s-manifests/mongo-deployment.yaml
    kubectl apply -f k8s-manifests/zookeeper-deployment.yaml
    kubectl apply -f k8s-manifests/kafka-deployment.yaml

    Write-Host "Waiting for Kafka to be Ready" -ForegroundColor Yellow
    do {
        $status = kubectl get pod -l io.kompose.service=kafka -o jsonpath='{.items[0].status.phase}' 2>$null
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 3
    } while ($status -ne "Running")
    Write-Host "`nKafka is online" -ForegroundColor Green
    
    Start-Sleep -Seconds 10 

    Write-Host "Initializing Topic with $Partitions Partitions" -ForegroundColor Cyan
    $topicCreated = $false
    while (-not $topicCreated) {
        try {
            kubectl exec deployment/kafka -- kafka-topics.sh --create --topic image_data --partitions $Partitions --replication-factor 1 --bootstrap-server localhost:29092 --if-not-exists 2>$null
            if ($LASTEXITCODE -eq 0) { $topicCreated = $true }
        } catch {
            Write-Host "Waiting for Kafka API" -ForegroundColor DarkGray
            Start-Sleep -Seconds 2
        }
    }
    Write-Host "Topic 'image_data' verified ($Partitions Partitions)" -ForegroundColor Green

    Write-Host "Launching Training job" -ForegroundColor Yellow
    kubectl apply -f k8s-manifests/train-model.yaml

    do {
        $podStatus = kubectl get pod -l job-name=model-trainer -o jsonpath='{.items[0].status.phase}' 2>$null
        Start-Sleep -Seconds 2
    } while ($podStatus -ne "Running" -and $podStatus -ne "Succeeded")
    
    kubectl logs -f job/model-trainer --timestamps
    kubectl wait --for=condition=complete --timeout=600s job/model-trainer
    Write-Host "Training complete" -ForegroundColor Green

    Write-Host "Deploying Monitoring Stack" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/prometheus-cm0-configmap.yaml
    kubectl apply -f k8s-manifests/prometheus-service.yaml
    kubectl apply -f k8s-manifests/grafana-service.yaml
    kubectl apply -f k8s-manifests/prometheus-deployment.yaml
    kubectl apply -f k8s-manifests/grafana-deployment.yaml

    Write-Host "Deploying Apps" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/consumer-service.yaml
    kubectl apply -f k8s-manifests/consumer-deployment.yaml
    
    kubectl apply -f k8s-manifests/consumer-hpa.yaml
    Write-Host "Horizontal Pod Autoscaler enabled" -ForegroundColor Green
    
    kubectl apply -f k8s-manifests/producer-deployment.yaml

    Write-Host "SYSTEM ONLINE" -ForegroundColor Green
    Write-Host "To access dashboards and storage, run in separate terminals:" -ForegroundColor Yellow
    Write-Host "  kubectl port-forward svc/grafana 3000:3000" -ForegroundColor Gray
    Write-Host "  kubectl port-forward svc/prometheus 9090:9090" -ForegroundColor Gray
    Write-Host "  kubectl port-forward service/mongo 27017:27017" -ForegroundColor Gray
    
    kubectl get pods
}