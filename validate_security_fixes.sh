#!/bin/bash

echo "=== Validating Security Fixes ==="
echo

# Check GitHub Actions fixes
echo "1. Checking GitHub Actions shell injection fixes..."
echo "   File: .github/workflows/deployment-stages.yml"

# Count problematic patterns
problematic_patterns=$(grep -E '\$\{\{.*\}\}' .github/workflows/deployment-stages.yml | grep -E 'run:.*\$\{\{' -A5 | grep -c '\${{' || echo 0)

if [ "$problematic_patterns" -eq 0 ]; then
    echo "   ✅ No shell injection vulnerabilities found"
else
    echo "   ❌ Found $problematic_patterns potential shell injection patterns"
fi

echo

# Check Kubernetes security contexts
echo "2. Checking Kubernetes security contexts..."

# Count containers without security context
total_containers=0
containers_with_security=0

# Check cronjobs
for file in k8s/cronjobs/**/*.yaml; do
    if grep -q "- name: scaler" "$file"; then
        total_containers=$((total_containers + 1))
        if grep -A5 "- name: scaler" "$file" | grep -q "securityContext:"; then
            containers_with_security=$((containers_with_security + 1))
        else
            echo "   ❌ Missing securityContext in: $file"
        fi
    fi
done

# Check deployments
for container in "league-updater" "shiny-updater"; do
    count=$(grep -c "- name: $container" k8s/k8s-deployment.yaml)
    total_containers=$((total_containers + count))
    
    # Check each occurrence
    while IFS= read -r line_num; do
        if sed -n "${line_num},$((line_num + 10))p" k8s/k8s-deployment.yaml | grep -q "securityContext:"; then
            containers_with_security=$((containers_with_security + 1))
        else
            echo "   ❌ Missing securityContext for $container at line $line_num in k8s-deployment.yaml"
        fi
    done < <(grep -n "- name: $container" k8s/k8s-deployment.yaml | cut -d: -f1)
done

echo "   Total containers: $total_containers"
echo "   Containers with security context: $containers_with_security"

if [ "$total_containers" -eq "$containers_with_security" ]; then
    echo "   ✅ All containers have security context configured"
else
    echo "   ❌ Some containers are missing security context"
fi

echo
echo "=== Summary ==="
if [ "$problematic_patterns" -eq 0 ] && [ "$total_containers" -eq "$containers_with_security" ]; then
    echo "✅ All security issues have been fixed!"
else
    echo "❌ Some security issues remain"
fi