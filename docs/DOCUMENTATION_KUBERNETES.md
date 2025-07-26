# Kubernetes Documentation

## Overview
Kubernetes (K8s) is a container orchestration platform that automates deployment, scaling, and management of containerized applications. This document covers essential manifest patterns and kubectl commands.

## Core Concepts

### Pods
The smallest deployable unit in Kubernetes:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: app
    image: nginx:1.21
    ports:
    - containerPort: 80
```

### Deployments
Manages replicated applications:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: myapp:1.0
        ports:
        - containerPort: 8080
```

### Services
Exposes applications:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  selector:
    app: myapp
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: ClusterIP  # or LoadBalancer, NodePort
```

## Manifest Patterns

### Complete Application Stack
```yaml
---
# Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: myapp-namespace

---
# ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: myapp-namespace
data:
  database.url: "postgres://db:5432/myapp"
  log.level: "info"

---
# Secret
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: myapp-namespace
type: Opaque
data:
  api-key: YXBpLWtleS12YWx1ZQ==  # base64 encoded

---
# PersistentVolumeClaim
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: myapp-namespace
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi

---
# Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-deployment
  namespace: myapp-namespace
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: myapp:1.0
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: database.url
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: api-key
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: data-pvc

---
# Service
apiVersion: v1
kind: Service
metadata:
  name: app-service
  namespace: myapp-namespace
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
  type: LoadBalancer
```

## Resource Management

### Resource Requests and Limits
```yaml
resources:
  requests:
    memory: "128Mi"    # Guaranteed minimum
    cpu: "100m"        # 0.1 CPU core
  limits:
    memory: "256Mi"    # Maximum allowed
    cpu: "200m"        # 0.2 CPU core
```

### Horizontal Pod Autoscaler
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Health Checks

### Liveness Probe
Restarts container if unhealthy:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

### Readiness Probe
Removes from service if not ready:
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  successThreshold: 1
  failureThreshold: 3
```

### Startup Probe
For slow-starting containers:
```yaml
startupProbe:
  httpGet:
    path: /startup
    port: 8080
  failureThreshold: 30
  periodSeconds: 10
```

## Storage Patterns

### EmptyDir (Temporary)
```yaml
volumes:
- name: cache
  emptyDir: {}
```

### HostPath (Node Storage)
```yaml
volumes:
- name: logs
  hostPath:
    path: /var/logs
    type: DirectoryOrCreate
```

### PersistentVolume & Claim
```yaml
# PersistentVolume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-data
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /mnt/data

---
# PersistentVolumeClaim
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-data
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
```

## Networking

### Service Types
```yaml
# ClusterIP (Internal only)
spec:
  type: ClusterIP
  
# NodePort (External via node port)
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080

# LoadBalancer (Cloud provider LB)
spec:
  type: LoadBalancer
```

### Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
```

## kubectl Commands

### Basic Operations
```bash
# Apply manifests
kubectl apply -f manifest.yaml
kubectl apply -f ./manifests/

# Get resources
kubectl get pods
kubectl get pods -n namespace
kubectl get all

# Describe resources
kubectl describe pod pod-name
kubectl describe deployment deployment-name

# Delete resources
kubectl delete -f manifest.yaml
kubectl delete pod pod-name
```

### Debugging
```bash
# View logs
kubectl logs pod-name
kubectl logs -f pod-name  # Follow logs
kubectl logs pod-name -c container-name  # Specific container

# Execute commands
kubectl exec -it pod-name -- /bin/bash
kubectl exec pod-name -- ls /app

# Port forwarding
kubectl port-forward pod-name 8080:80
kubectl port-forward service/service-name 8080:80

# Get events
kubectl get events --sort-by=.metadata.creationTimestamp
```

### Resource Management
```bash
# Scale deployments
kubectl scale deployment app --replicas=5

# Update image
kubectl set image deployment/app app=myapp:2.0

# Rollout management
kubectl rollout status deployment/app
kubectl rollout history deployment/app
kubectl rollout undo deployment/app
```

### Configuration
```bash
# Create ConfigMap from file
kubectl create configmap app-config --from-file=config.properties

# Create Secret
kubectl create secret generic app-secret --from-literal=password=mypassword

# Edit resources
kubectl edit deployment app

# Apply with dry-run
kubectl apply -f manifest.yaml --dry-run=client
```

## Best Practices

### 1. Label Everything
```yaml
metadata:
  labels:
    app: myapp
    version: "1.0"
    environment: production
    team: backend
```

### 2. Use Namespaces
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    env: prod
```

### 3. Set Resource Limits
Always define requests and limits:
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

### 4. Use Probes
Always configure health checks:
```yaml
livenessProbe:
  httpGet:
    path: /health
readinessProbe:
  httpGet:
    path: /ready
```

### 5. Security Context
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  capabilities:
    drop:
    - ALL
```

## Advanced Patterns

### Blue-Green Deployment
```bash
# Deploy green version
kubectl apply -f green-deployment.yaml

# Switch service to green
kubectl patch service myapp -p '{"spec":{"selector":{"version":"green"}}}'

# Delete blue version
kubectl delete deployment blue-deployment
```

### Canary Deployment
```yaml
# 10% traffic to canary
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp  # Selects both stable and canary
```

### StatefulSet for Databases
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:14
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

## Troubleshooting

### Common Issues

1. **Pod Stuck in Pending**
   ```bash
   kubectl describe pod pod-name
   # Check events for scheduling issues
   ```

2. **CrashLoopBackOff**
   ```bash
   kubectl logs pod-name --previous
   # Check container exit logs
   ```

3. **ImagePullBackOff**
   ```bash
   kubectl describe pod pod-name
   # Check image name and registry credentials
   ```

4. **Service Not Accessible**
   ```bash
   kubectl get endpoints service-name
   # Verify selector matches pod labels
   ```

### Debug Commands
```bash
# Get detailed pod info
kubectl get pod pod-name -o yaml

# Check resource usage
kubectl top nodes
kubectl top pods

# Validate manifests
kubectl apply -f manifest.yaml --dry-run=client --validate=true

# Get pod IPs
kubectl get pods -o wide
```