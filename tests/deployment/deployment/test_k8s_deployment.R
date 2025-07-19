# Kubernetes Deployment Validation Tests
# Tests for Kubernetes manifests and deployment configurations

library(testthat)
library(yaml)
library(jsonlite)

context("Kubernetes deployment validation")

test_that("Kubernetes deployment manifests are valid", {
  skip_if_not(file.exists("k8s/deployment.yaml"),
              "Kubernetes manifests not found")
  
  # Read deployment manifest
  deployment_yaml <- yaml::read_yaml("k8s/deployment.yaml")
  
  # Validate structure
  expect_equal(deployment_yaml$apiVersion, "apps/v1",
               info = "Deployment should use apps/v1 API")
  
  expect_equal(deployment_yaml$kind, "Deployment",
               info = "Kind should be Deployment")
  
  # Check metadata
  expect_true(!is.null(deployment_yaml$metadata$name),
              info = "Deployment must have a name")
  
  expect_true(!is.null(deployment_yaml$metadata$labels),
              info = "Deployment should have labels")
  
  # Check spec
  spec <- deployment_yaml$spec
  
  expect_true(!is.null(spec$replicas),
              info = "Replicas should be specified")
  
  expect_gte(spec$replicas, 2,
             info = "Should have at least 2 replicas for HA")
  
  # Check selector
  expect_true(!is.null(spec$selector$matchLabels),
              info = "Selector must have matchLabels")
  
  # Check template
  template <- spec$template
  
  expect_true(!is.null(template$metadata$labels),
              info = "Pod template must have labels")
  
  # Labels must match selector
  expect_true(all(names(spec$selector$matchLabels) %in% names(template$metadata$labels)),
              info = "Template labels must include selector labels")
  
  # Check container spec
  containers <- template$spec$containers
  expect_length(containers, 1,
                info = "Should have exactly one container")
  
  container <- containers[[1]]
  
  expect_true(!is.null(container$name),
              info = "Container must have a name")
  
  expect_true(!is.null(container$image),
              info = "Container must specify an image")
  
  # Check probes
  expect_true(!is.null(container$livenessProbe),
              info = "Container should have liveness probe")
  
  expect_true(!is.null(container$readinessProbe),
              info = "Container should have readiness probe")
  
  # Check resource limits
  expect_true(!is.null(container$resources),
              info = "Container should specify resources")
  
  if (!is.null(container$resources)) {
    expect_true(!is.null(container$resources$limits),
                info = "Should specify resource limits")
    expect_true(!is.null(container$resources$requests),
                info = "Should specify resource requests")
  }
})

test_that("Service configuration is correct", {
  skip_if_not(file.exists("k8s/service.yaml"),
              "Service manifest not found")
  
  service_yaml <- yaml::read_yaml("k8s/service.yaml")
  
  expect_equal(service_yaml$apiVersion, "v1",
               info = "Service should use v1 API")
  
  expect_equal(service_yaml$kind, "Service",
               info = "Kind should be Service")
  
  # Check spec
  spec <- service_yaml$spec
  
  expect_true(!is.null(spec$selector),
              info = "Service must have selector")
  
  expect_true(!is.null(spec$ports),
              info = "Service must specify ports")
  
  # Check port configuration
  for (port in spec$ports) {
    expect_true(!is.null(port$port),
                info = "Port must specify port number")
    expect_true(!is.null(port$targetPort),
                info = "Port must specify targetPort")
    expect_true(!is.null(port$protocol),
                info = "Port should specify protocol")
  }
  
  # Check type
  expect_true(spec$type %in% c("ClusterIP", "NodePort", "LoadBalancer"),
              info = "Service type must be valid")
})

test_that("ConfigMap contains required configuration", {
  skip_if_not(file.exists("k8s/configmap.yaml"),
              "ConfigMap not found")
  
  configmap_yaml <- yaml::read_yaml("k8s/configmap.yaml")
  
  expect_equal(configmap_yaml$apiVersion, "v1",
               info = "ConfigMap should use v1 API")
  
  expect_equal(configmap_yaml$kind, "ConfigMap",
               info = "Kind should be ConfigMap")
  
  # Check data
  data <- configmap_yaml$data
  
  required_configs <- c("app.conf", "logging.conf")
  
  for (config in required_configs) {
    expect_true(config %in% names(data),
                info = sprintf("ConfigMap should contain %s", config))
  }
})

test_that("Secrets are properly configured", {
  skip_if_not(file.exists("k8s/secret-template.yaml"),
              "Secret template not found")
  
  secret_yaml <- yaml::read_yaml("k8s/secret-template.yaml")
  
  expect_equal(secret_yaml$apiVersion, "v1",
               info = "Secret should use v1 API")
  
  expect_equal(secret_yaml$kind, "Secret",
               info = "Kind should be Secret")
  
  expect_equal(secret_yaml$type, "Opaque",
               info = "Secret type should be Opaque")
  
  # Check that data fields are placeholders
  if (!is.null(secret_yaml$data)) {
    for (key in names(secret_yaml$data)) {
      value <- secret_yaml$data[[key]]
      expect_true(grepl("PLACEHOLDER|CHANGE_ME|<.*>", value),
                  info = sprintf("Secret %s should be a placeholder", key))
    }
  }
})

test_that("Horizontal Pod Autoscaler is configured", {
  skip_if_not(file.exists("k8s/hpa.yaml"),
              "HPA manifest not found")
  
  hpa_yaml <- yaml::read_yaml("k8s/hpa.yaml")
  
  expect_true(hpa_yaml$apiVersion %in% c("autoscaling/v1", "autoscaling/v2"),
              info = "HPA should use valid API version")
  
  expect_equal(hpa_yaml$kind, "HorizontalPodAutoscaler",
               info = "Kind should be HorizontalPodAutoscaler")
  
  # Check spec
  spec <- hpa_yaml$spec
  
  expect_true(!is.null(spec$scaleTargetRef),
              info = "HPA must specify scale target")
  
  expect_equal(spec$scaleTargetRef$kind, "Deployment",
               info = "HPA should target Deployment")
  
  # Check scaling parameters
  expect_true(!is.null(spec$minReplicas),
              info = "HPA should specify minReplicas")
  
  expect_true(!is.null(spec$maxReplicas),
              info = "HPA should specify maxReplicas")
  
  expect_gte(spec$maxReplicas, spec$minReplicas,
             info = "maxReplicas must be >= minReplicas")
  
  # Check metrics
  if (hpa_yaml$apiVersion == "autoscaling/v2") {
    expect_true(!is.null(spec$metrics),
                info = "HPA v2 should specify metrics")
  } else {
    expect_true(!is.null(spec$targetCPUUtilizationPercentage),
                info = "HPA v1 should specify CPU target")
  }
})

test_that("Network policies are defined", {
  skip_if_not(file.exists("k8s/network-policy.yaml"),
              "Network policy not found")
  
  netpol_yaml <- yaml::read_yaml("k8s/network-policy.yaml")
  
  expect_equal(netpol_yaml$apiVersion, "networking.k8s.io/v1",
               info = "NetworkPolicy should use networking.k8s.io/v1")
  
  expect_equal(netpol_yaml$kind, "NetworkPolicy",
               info = "Kind should be NetworkPolicy")
  
  # Check spec
  spec <- netpol_yaml$spec
  
  expect_true(!is.null(spec$podSelector),
              info = "NetworkPolicy must have podSelector")
  
  # Check policy types
  expect_true(!is.null(spec$policyTypes),
              info = "NetworkPolicy should specify policyTypes")
  
  # If ingress is specified, check rules
  if ("Ingress" %in% spec$policyTypes) {
    expect_true(!is.null(spec$ingress),
                info = "Ingress rules should be defined")
  }
  
  # If egress is specified, check rules
  if ("Egress" %in% spec$policyTypes) {
    expect_true(!is.null(spec$egress),
                info = "Egress rules should be defined")
  }
})

test_that("PersistentVolumeClaim is configured correctly", {
  skip_if_not(file.exists("k8s/pvc.yaml"),
              "PVC manifest not found")
  
  pvc_yaml <- yaml::read_yaml("k8s/pvc.yaml")
  
  expect_equal(pvc_yaml$apiVersion, "v1",
               info = "PVC should use v1 API")
  
  expect_equal(pvc_yaml$kind, "PersistentVolumeClaim",
               info = "Kind should be PersistentVolumeClaim")
  
  # Check spec
  spec <- pvc_yaml$spec
  
  expect_true(!is.null(spec$accessModes),
              info = "PVC must specify access modes")
  
  expect_true(any(spec$accessModes %in% c("ReadWriteOnce", "ReadOnlyMany", "ReadWriteMany")),
              info = "PVC must have valid access mode")
  
  # Check resources
  expect_true(!is.null(spec$resources$requests$storage),
              info = "PVC must request storage size")
  
  # Parse storage size
  storage <- spec$resources$requests$storage
  expect_true(grepl("^[0-9]+(Ki|Mi|Gi|Ti)$", storage),
              info = "Storage size must be in valid format")
})

test_that("Deployment strategy is appropriate", {
  skip_if_not(file.exists("k8s/deployment.yaml"),
              "Deployment manifest not found")
  
  deployment_yaml <- yaml::read_yaml("k8s/deployment.yaml")
  strategy <- deployment_yaml$spec$strategy
  
  expect_true(!is.null(strategy),
              info = "Deployment should specify strategy")
  
  expect_true(strategy$type %in% c("RollingUpdate", "Recreate"),
              info = "Strategy type must be valid")
  
  if (strategy$type == "RollingUpdate") {
    expect_true(!is.null(strategy$rollingUpdate),
                info = "RollingUpdate should have parameters")
    
    # Check rolling update parameters
    ru <- strategy$rollingUpdate
    
    if (!is.null(ru$maxSurge)) {
      expect_true(grepl("^[0-9]+(%)?$", as.character(ru$maxSurge)),
                  info = "maxSurge must be number or percentage")
    }
    
    if (!is.null(ru$maxUnavailable)) {
      expect_true(grepl("^[0-9]+(%)?$", as.character(ru$maxUnavailable)),
                  info = "maxUnavailable must be number or percentage")
    }
  }
})

test_that("Security context is defined", {
  skip_if_not(file.exists("k8s/deployment.yaml"),
              "Deployment manifest not found")
  
  deployment_yaml <- yaml::read_yaml("k8s/deployment.yaml")
  pod_spec <- deployment_yaml$spec$template$spec
  
  # Check pod-level security context
  expect_true(!is.null(pod_spec$securityContext),
              info = "Pod should have security context")
  
  if (!is.null(pod_spec$securityContext)) {
    # Should not run as root
    if (!is.null(pod_spec$securityContext$runAsNonRoot)) {
      expect_true(pod_spec$securityContext$runAsNonRoot,
                  info = "Pod should run as non-root")
    }
    
    # Should have user ID
    if (!is.null(pod_spec$securityContext$runAsUser)) {
      expect_gt(pod_spec$securityContext$runAsUser, 0,
                info = "Should specify non-root user ID")
    }
  }
  
  # Check container-level security context
  container <- pod_spec$containers[[1]]
  
  if (!is.null(container$securityContext)) {
    # Should not allow privilege escalation
    if (!is.null(container$securityContext$allowPrivilegeEscalation)) {
      expect_false(container$securityContext$allowPrivilegeEscalation,
                   info = "Should not allow privilege escalation")
    }
    
    # Should be read-only root filesystem
    if (!is.null(container$securityContext$readOnlyRootFilesystem)) {
      expect_true(container$securityContext$readOnlyRootFilesystem,
                  info = "Root filesystem should be read-only")
    }
  }
})