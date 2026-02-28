#!/bin/bash

set -e

echo "Installing Velero for Kubernetes homelab..."

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Install CRDs
echo -e "${YELLOW}Step 1: Installing Velero CRDs...${NC}"
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/v1.13.0/config/crd/v1/crds.yaml

# Wait for CRDs to be established
echo "Waiting for CRDs to be ready..."
sleep 5

# Step 2: Deploy Velero
echo -e "${YELLOW}Step 2: Deploying Velero...${NC}"
kubectl apply -k .

# Step 3: Wait for Velero to be ready
echo -e "${YELLOW}Step 3: Waiting for Velero to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s

# Step 4: Verify installation
echo -e "${YELLOW}Step 4: Verifying installation...${NC}"
kubectl get pods -n velero
kubectl get backupstoragelocations -n velero
kubectl get volumesnapshotlocations -n velero
kubectl get volumesnapshotclass

echo -e "${GREEN}Velero installation complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Verify BackupStorageLocation is available:"
echo "   kubectl get backupstoragelocations -n velero"
echo ""
echo "2. Create your first backup:"
echo "   velero backup create test-backup --include-namespaces default"
echo ""
echo "3. Deploy example schedules:"
echo "   kubectl apply -f examples/daily-backup.yaml"
echo "   kubectl apply -f examples/weekly-full-backup.yaml"
echo ""
echo "4. Check Velero status:"
echo "   kubectl logs -n velero -l app.kubernetes.io/name=velero"

