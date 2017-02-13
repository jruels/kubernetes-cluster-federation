# Create GKE clusters
echo "Creating Asia-East-1 Cluster"
gcloud container clusters create gce-asia-east1 --zone asia-east1-b --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
echo "Creating Europe-West-1 Cluster"
gcloud container clusters create gce-europe-west1 --zone=europe-west1-b --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
echo "Creating US-East-1 Cluster"
gcloud container clusters create gce-us-east1 --zone=us-east1-b --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
echo "Creating US-Central-1 Cluster"
gcloud container clusters create gce-us-central1 --zone=us-central1-b --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
echo "Waiting 30 Seconds while Kubernetes becomes available"
echo "Get cluster credentials"
gcloud container clusters get-credentials gce-asia-east1 --zone=asia-east1-b
gcloud container clusters get-credentials gce-europe-west1 --zone=europe-west1-b
gcloud container clusters get-credentials gce-us-east1 --zone=us-east1-b
gcloud container clusters get-credentials gce-us-central1 --zone=us-central1-b
echo "Setting environment variable for project name"
export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
echo "Create cluster config for Asia-East-1"
kubectl config use-context "gke_${GCP_PROJECT}_asia-east1-b_gce-asia-east1"
ASIA_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > clusters/gce-asia-east1.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: gce-asia-east1
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${ASIA_SERVER_ADDRESS}"
  secretRef:
    name: gce-asia-east1
EOF
kubectl config view --flatten --minify > kubeconfigs/gce-asia-east1/kubeconfig
echo "Create cluster config for Europe-West-1"
kubectl config use-context "gke_${GCP_PROJECT}_europe-west1-b_gce-europe-west1"
EUROPE_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > clusters/gce-europe-west1.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: gce-europe-west1
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${EUROPE_SERVER_ADDRESS}"
  secretRef:
    name: gce-europe-west1
EOF
kubectl config view --flatten --minify > kubeconfigs/gce-europe-west1/kubeconfig
echo "Create cluster config for US-Central-1"
kubectl config use-context "gke_${GCP_PROJECT}_us-central1-b_gce-us-central1"
US_CENTRAL_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > clusters/gce-us-central1.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: gce-us-central1
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${US_CENTRAL_SERVER_ADDRESS}"
  secretRef:
    name: gce-us-central1
EOF
kubectl config view --flatten --minify > kubeconfigs/gce-us-central1/kubeconfig
echo "Create cluster config for US-Central-1"
kubectl config use-context "gke_${GCP_PROJECT}_us-east1-b_gce-us-east1"
US_EAST_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > clusters/gce-us-east1.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: gce-us-east1
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${US_EAST_SERVER_ADDRESS}"
  secretRef:
    name: gce-us-east1
EOF
kubectl config view --flatten --minify > kubeconfigs/gce-us-east1/kubeconfig
# Create Federation Control Plane
echo "Create Federation Namespace"
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" create -f ns/federation.yaml
echo "Create Federation API Server Service"
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" create -f services/federation-apiserver.yaml
echo "Wait for 60 Seconds until the API server becomes available"
sleep 60
echo "Creating Federation secrets"
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation create secret generic federation-apiserver-secrets --from-file=known-tokens.csv
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation describe secrets federation-apiserver-secrets
echo "Creating Persistent Disk"
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation create -f pvc/federation-apiserver-etcd.yaml
echo "Creating the Deployment"
FEDERATED_API_SERVER_ADDRESS=$(kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation get services federation-apiserver -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
sed -i "s|ADVERTISE_ADDRESS|${FEDERATED_API_SERVER_ADDRESS}|g" deployments/federation-apiserver.yaml
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation create -f deployments/federation-apiserver.yaml
#Create the Federation context
FEDERATED_API_SERVER_ADDRESS=$(kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation get services federation-apiserver -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
kubectl config set-cluster federation-cluster --server=https://${FEDERATED_API_SERVER_ADDRESS} --insecure-skip-tls-verify=true
FEDERATION_CLUSTER_TOKEN=$(cut -d"," -f1 known-tokens.csv)
kubectl config set-credentials federation-cluster --token=${FEDERATION_CLUSTER_TOKEN}
kubectl config set-context federation-cluster --cluster=federation-cluster --user=federation-cluster
kubectl config use-context federation-cluster
kubectl config view --flatten --minify > kubeconfigs/federation-apiserver/kubeconfig
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation create secret generic federation-apiserver-kubeconfig --from-file=kubeconfigs/federation-apiserver/kubeconfig
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation describe secrets federation-apiserver-kubeconfig
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation create -f deployments/federation-controller-manager.yaml
echo "Waiting 60 seconds whil the Federation controller becomes available"
# Add Clusters to Federation
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation create secret generic gce-asia-east1 --from-file=kubeconfigs/gce-asia-east1/kubeconfig
kubectl --context=federation-cluster create -f clusters/gce-asia-east1.yaml
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation create secret generic gce-europe-west1 --from-file=kubeconfigs/gce-europe-west1/kubeconfig
kubectl --context=federation-cluster create -f clusters/gce-europe-west1.yaml
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation create secret generic gce-us-central1 --from-file=kubeconfigs/gce-us-central1/kubeconfig
kubectl --context=federation-cluster create -f clusters/gce-us-central1.yaml
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" --namespace=federation create secret generic gce-us-east1 --from-file=kubeconfigs/gce-us-east1/kubeconfig
kubectl --context=federation-cluster create -f clusters/gce-us-east1.yaml
