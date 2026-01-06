param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("start", "stop")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [int]$Partitions = 8,

    [Parameter(Mandatory=$false)]
    [int]$CPUs = 8,

    [Parameter(Mandatory=$false)]
    [int]$Memory = 20480
)

if ($Action -eq "stop") {
    Write-Host "Shutting down the cluster" -ForegroundColor Yellow
    kubectl scale deployment consumer --replicas=0 2>$null

    kubectl delete deployment producer consumer kafka zookeeper mongo prometheus grafana --ignore-not-found
    kubectl delete job model-trainer --ignore-not-found
    kubectl delete service kafka zookeeper mongo prometheus grafana consumer --ignore-not-found
    kubectl delete configmap prometheus-cm0 consumer-env --ignore-not-found
    kubectl delete hpa consumer-hpa --ignore-not-found
    kubectl delete pvc discoveries-pvc --ignore-not-found
    minikube stop
    Write-Host "Shutdown Complete" -ForegroundColor Green
}

if ($Action -eq "start") {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Starting Kubernetes GPU Cluster" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "CPUs: $CPUs | Memory: $Memory MB | Partitions: $Partitions" -ForegroundColor Gray
    Write-Host ""

    # Start Minikube with GPU and resources
    Write-Host "[1/10] Starting Minikube with GPU" -ForegroundColor Cyan
    minikube start --driver=docker --gpus all --cpus $CPUs --memory $Memory

    # Configure GPU Time-Slicing
    Write-Host "[2/10] Configuring GPU Time-Slicing" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/gpu-sharing-config.yaml
    kubectl apply -f k8s-manifests/nvidia-device-plugin.yaml
    
    # Restart device plugin pod to pick up new config
    kubectl rollout restart daemonset nvidia-device-plugin-daemonset -n kube-system
    Start-Sleep -Seconds 5
    kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n kube-system --timeout=60s

    # Wait for GPU slices
    Write-Host "Waiting for GPU time-slicing to activate" -ForegroundColor Yellow
    $gpuCount = 0
    $attempts = 0
    while ($gpuCount -lt 8 -and $attempts -lt 30) {
        Start-Sleep -Seconds 2
        $gpuJson = kubectl get nodes -o json 2>$null | ConvertFrom-Json
        $gpuCount = $gpuJson.items[0].status.allocatable.'nvidia.com/gpu'
        $attempts++
        Write-Host -NoNewline "."
    }
    Write-Host ""

    if ($gpuCount -ge 8) {
        Write-Host "GPU Time-Slicing active: $gpuCount GPU slices available" -ForegroundColor Green
    } else {
        Write-Host "Warning: GPU count is $gpuCount (expected 8). Continuing..." -ForegroundColor Yellow
    }

    # Build Docker Image
    Write-Host "[3/10] Building Docker Image" -ForegroundColor Cyan
    minikube image build -t ml-inference-app:latest .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Image build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Image built successfully" -ForegroundColor Green

    # Deploy Storage and Config
    Write-Host "[4/10] Deploying Storage and Config" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/discoveries-pvc.yaml
    kubectl create configmap consumer-env --from-env-file=.env --dry-run=client -o yaml | kubectl apply -f -

    # Deploy Infrastructure Services
    Write-Host "[5/10] Deploying Infrastructure (Mongo, Zookeeper, Kafka)" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/mongo-service.yaml
    kubectl apply -f k8s-manifests/zookeeper-service.yaml
    kubectl apply -f k8s-manifests/kafka-service.yaml
    kubectl apply -f k8s-manifests/mongo-deployment.yaml
    kubectl apply -f k8s-manifests/zookeeper-deployment.yaml
    kubectl apply -f k8s-manifests/kafka-deployment.yaml

    # Wait for Kafka
    Write-Host "Waiting for Kafka to be ready" -ForegroundColor Yellow
    do {
        $status = kubectl get pod -l io.kompose.service=kafka -o jsonpath='{.items[0].status.phase}' 2>$null
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 3
    } while ($status -ne "Running")
    Write-Host ""
    Write-Host "Kafka is online" -ForegroundColor Green

    Start-Sleep -Seconds 10

    # Create Kafka Topic
    Write-Host "[6/10] Creating Kafka Topic ($Partitions partitions)" -ForegroundColor Cyan
    $topicCreated = $false
    $topicAttempts = 0
    while (-not $topicCreated -and $topicAttempts -lt 10) {
        kubectl exec deployment/kafka -- kafka-topics.sh --create --topic image_data --partitions $Partitions --replication-factor 1 --bootstrap-server localhost:29092 --if-not-exists 2>$null
        if ($LASTEXITCODE -eq 0) { 
            $topicCreated = $true 
        } else {
            $topicAttempts++
            Write-Host "Retrying topic creation..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 3
        }
    }
    if ($topicCreated) {
        Write-Host "Topic 'image_data' created ($Partitions partitions)" -ForegroundColor Green
    } else {
        Write-Host "Warning: Topic creation may have failed" -ForegroundColor Yellow
    }

    # Train Model
    Write-Host "[7/10] Training ML Model" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/train-model.yaml

    Write-Host "Waiting for training to start" -ForegroundColor Yellow
    $trainingStarted = $false
    while (-not $trainingStarted) {
        $podStatus = kubectl get pod -l job-name=model-trainer -o jsonpath='{.items[0].status.phase}' 2>$null
        if ($podStatus -eq "Running" -or $podStatus -eq "Succeeded") {
            $trainingStarted = $true
        }
        Start-Sleep -Seconds 2
    }

    kubectl logs -f job/model-trainer --timestamps
    kubectl wait --for=condition=complete --timeout=600s job/model-trainer
    Write-Host "Training complete" -ForegroundColor Green

    # Deploy Monitoring
    Write-Host "[8/10] Deploying Monitoring (Prometheus, Grafana)" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/prometheus-cm0-configmap.yaml
    kubectl apply -f k8s-manifests/prometheus-service.yaml
    kubectl apply -f k8s-manifests/grafana-service.yaml
    kubectl apply -f k8s-manifests/prometheus-deployment.yaml
    kubectl apply -f k8s-manifests/grafana-deployment.yaml

    # Deploy Consumer
    Write-Host "[9/10] Deploying Consumer with HPA" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/consumer-service.yaml
    kubectl apply -f k8s-manifests/consumer-deployment.yaml
    kubectl apply -f k8s-manifests/consumer-hpa.yaml
    minikube addons disable metrics-server 2>$null
    minikube addons enable metrics-server
    Start-Sleep -Seconds 5

    # Deploy Producer
    Write-Host "[10/10] Deploying Producer" -ForegroundColor Cyan
    kubectl apply -f k8s-manifests/producer-deployment.yaml

    # Wait for pods to stabilize
    Write-Host "Waiting for pods to be ready" -ForegroundColor Yellow
    Start-Sleep -Seconds 10

    # Final Status
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "        SYSTEM ONLINE" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor Cyan
    Write-Host "  GPU Slices:       $gpuCount" -ForegroundColor White
    Write-Host "  Kafka Partitions: $Partitions" -ForegroundColor White
    Write-Host "  HPA Range:        1-8 pods" -ForegroundColor White
    Write-Host ""
    Write-Host "Access Dashboards:" -ForegroundColor Yellow
    Write-Host "  kubectl port-forward svc/grafana 3000:3000" -ForegroundColor Gray
    Write-Host "  kubectl port-forward svc/prometheus 9090:9090" -ForegroundColor Gray
    Write-Host "  kubectl port-forward svc/mongo 27017:27017" -ForegroundColor Gray
    Write-Host ""

    kubectl get pods
}