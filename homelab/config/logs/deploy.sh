#!/bin/bash

# Kubernetes Log Management Deployment Script
# This script deploys the comprehensive log management system

set -e

NAMESPACE="kube-system"
LOG_NAMESPACE="log-management"

echo "🚀 Deploying Kubernetes Log Management System..."

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl not found. Please install kubectl first."
        exit 1
    fi
}

# Function to check cluster connectivity
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        echo "❌ Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    echo "✅ Connected to Kubernetes cluster"
}

# Function to validate YAML files
validate_yaml() {
    echo "🔍 Validating YAML configurations..."
    
    for file in *.yaml; do
        if [[ "$file" != "kustomization.yaml" ]]; then
            echo "  Validating $file..."
            kubectl apply --dry-run=client -f "$file" > /dev/null 2>&1 || {
                echo "❌ Validation failed for $file"
                exit 1
            }
        fi
    done
    
    echo "✅ All YAML files are valid"
}

# Function to deploy log management
deploy_log_management() {
    echo "📦 Deploying log management components..."
    
    # Apply the kustomization
    kubectl apply -k . || {
        echo "❌ Failed to deploy log management system"
        exit 1
    }
    
    echo "✅ Log management system deployed successfully"
}

# Function to wait for deployment
wait_for_deployment() {
    echo "⏳ Waiting for components to be ready..."
    
    # Wait for DaemonSet to be ready
    kubectl rollout status daemonset/logrotate -n "$NAMESPACE" --timeout=300s || {
        echo "❌ LogRotate DaemonSet failed to start"
        exit 1
    }
    
    echo "✅ LogRotate DaemonSet is ready"
    
    # Check if CronJob was created
    if kubectl get cronjob log-cleanup -n "$NAMESPACE" &> /dev/null; then
        echo "✅ Log cleanup CronJob created"
    else
        echo "❌ Log cleanup CronJob not found"
        exit 1
    fi
}

# Function to show status
show_status() {
    echo ""
    echo "📊 Log Management System Status:"
    echo "================================"
    
    echo ""
    echo "🔄 DaemonSet Status:"
    kubectl get ds logrotate -n "$NAMESPACE" -o wide
    
    echo ""
    echo "⏰ CronJob Status:"
    kubectl get cronjob log-cleanup -n "$NAMESPACE"
    
    echo ""
    echo "📋 Recent Jobs:"
    kubectl get jobs -n "$NAMESPACE" | grep log-cleanup | head -5
    
    echo ""
    echo "🏷️  ConfigMaps:"
    kubectl get cm -n "$NAMESPACE" | grep -E "(logrotate-config|container-log-policy)"
    
    echo ""
    echo "📊 Node Disk Usage:"
    kubectl exec -n "$NAMESPACE" ds/logrotate -- df -h /host/var/log 2>/dev/null | head -2 || echo "  (LogRotate pods not ready yet)"
}

# Function to show next steps
show_next_steps() {
    echo ""
    echo "🎉 Deployment Complete!"
    echo "======================"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor the system:"
    echo "   kubectl logs -n $NAMESPACE -l app=logrotate -f"
    echo ""
    echo "2. Check log cleanup job:"
    echo "   kubectl logs -n $NAMESPACE job/\$(kubectl get jobs -n $NAMESPACE | grep log-cleanup | tail -1 | awk '{print \$1}')"
    echo ""
    echo "3. Manual cleanup if needed:"
    echo "   kubectl create job --from=cronjob/log-cleanup manual-cleanup -n $NAMESPACE"
    echo ""
    echo "4. View comprehensive status:"
    echo "   kubectl get all -n $NAMESPACE | grep -E '(logrotate|log-cleanup)'"
    echo ""
    echo "📖 For more information, see: homelab/config/logs/README.md"
}

# Main execution
main() {
    echo "🔧 Kubernetes Log Management Deployment"
    echo "======================================="
    
    # Change to the logs directory
    cd "$(dirname "$0")"
    
    # Run checks
    check_kubectl
    check_cluster
    validate_yaml
    
    # Deploy
    deploy_log_management
    wait_for_deployment
    
    # Show results
    show_status
    show_next_steps
}

# Run main function
main "$@"
