# Clean up session crud
rm -f ~/.kube/config
# Create GKE clusters
echo "Creating Asia Cluster"
gcloud container clusters create sockshop-asia --zone asia-east1-b --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
echo "Creating Europe Cluster"
gcloud container clusters create sockshop-europe --zone=europe-west1-b --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
echo "Creating US East Cluster"
gcloud container clusters create sockshop-useast --zone=us-east1-b --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
echo "Creating US Central Cluster"
gcloud container clusters create sockshop-uscentral --zone=us-central1-b --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
echo "Waiting 30 Seconds while Kubernetes becomes available"
sleep 30
echo "Get cluster credentials"
gcloud container clusters get-credentials sockshop-asia --zone=asia-east1-b
gcloud container clusters get-credentials sockshop-europe --zone=europe-west1-b
gcloud container clusters get-credentials sockshop-useast --zone=us-east1-b
gcloud container clusters get-credentials sockshop-uscentral --zone=us-central1-b
echo "Setting environment variable for project name"
export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
echo "Create cluster config for Asia-East-1"
kubectl config use-context "gke_${GCP_PROJECT}_asia-east1-b_sockshop-asia"
ASIA_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > clusters/sockshop-asia.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: sockshop-asia
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${ASIA_SERVER_ADDRESS}"
  secretRef:
    name: sockshop-asia
EOF
kubectl config view --flatten --minify > kubeconfigs/sockshop-asia/kubeconfig
echo "Create cluster config for Europe-West-1"
kubectl config use-context "gke_${GCP_PROJECT}_europe-west1-b_sockshop-europe"
EUROPE_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > clusters/sockshop-europe.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: sockshop-europe
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${EUROPE_SERVER_ADDRESS}"
  secretRef:
    name: sockshop-europe
EOF
kubectl config view --flatten --minify > kubeconfigs/sockshop-europe/kubeconfig
echo "Create cluster config for US-Central-1"
kubectl config use-context "gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral"
US_CENTRAL_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > clusters/sockshop-uscentral.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: sockshop-uscentral
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${US_CENTRAL_SERVER_ADDRESS}"
  secretRef:
    name: sockshop-uscentral
EOF
kubectl config view --flatten --minify > kubeconfigs/sockshop-uscentral/kubeconfig
echo "Create cluster config for US-Central-1"
kubectl config use-context "gke_${GCP_PROJECT}_us-east1-b_sockshop-useast"
US_EAST_SERVER_ADDRESS=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > clusters/sockshop-useast.yaml <<EOF
apiVersion: federation/v1beta1
kind: Cluster
metadata:
  name: sockshop-useast
spec:
  serverAddressByClientCIDRs:
    - clientCIDR: "0.0.0.0/0"
      serverAddress: "${US_EAST_SERVER_ADDRESS}"
  secretRef:
    name: sockshop-useast
EOF
kubectl config view --flatten --minify > kubeconfigs/sockshop-useast/kubeconfig
# Create Federation Control Plane
echo "Create Federation Namespace"
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" create -f ns/federation.yaml
echo "Create Federation API Server Service"
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" create -f services/federation-apiserver.yaml
echo "Wait for 90 Seconds until the API server becomes available"
sleep 90
echo "Creating Federation secrets"
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation create secret generic federation-apiserver-secrets --from-file=known-tokens.csv
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation describe secrets federation-apiserver-secrets
echo "Creating Persistent Disk"
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation create -f pvc/federation-apiserver-etcd.yaml
echo "Creating the Deployment"
FEDERATED_API_SERVER_ADDRESS=$(kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation get services federation-apiserver -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
sed -i "s|ADVERTISE_ADDRESS|${FEDERATED_API_SERVER_ADDRESS}|g" deployments/federation-apiserver.yaml
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation create -f deployments/federation-apiserver.yaml
#Create the Federation context
FEDERATED_API_SERVER_ADDRESS=$(kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation get services federation-apiserver -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
kubectl config set-cluster federation-cluster --server=https://${FEDERATED_API_SERVER_ADDRESS} --insecure-skip-tls-verify=true
FEDERATION_CLUSTER_TOKEN=$(cut -d"," -f1 known-tokens.csv)
kubectl config set-credentials federation-cluster --token=${FEDERATION_CLUSTER_TOKEN}
kubectl config set-context federation-cluster --cluster=federation-cluster --user=federation-cluster
kubectl config use-context federation-cluster
kubectl config view --flatten --minify > kubeconfigs/federation-apiserver/kubeconfig
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation create secret generic federation-apiserver-kubeconfig --from-file=kubeconfigs/federation-apiserver/kubeconfig
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation describe secrets federation-apiserver-kubeconfig
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation create -f deployments/federation-controller-manager.yaml
echo "Waiting 60 seconds while the Federation controller becomes available"
sleep 60
# Add Clusters to Federation
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation create secret generic sockshop-asia --from-file=kubeconfigs/sockshop-asia/kubeconfig
kubectl --context=federation-cluster create -f clusters/sockshop-asia.yaml
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation create secret generic sockshop-europe --from-file=kubeconfigs/sockshop-europe/kubeconfig
kubectl --context=federation-cluster create -f clusters/sockshop-europe.yaml
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation create secret generic sockshop-uscentral --from-file=kubeconfigs/sockshop-uscentral/kubeconfig
kubectl --context=federation-cluster create -f clusters/sockshop-uscentral.yaml
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_sockshop-uscentral" --namespace=federation create secret generic sockshop-useast --from-file=kubeconfigs/sockshop-useast/kubeconfig
kubectl --context=federation-cluster create -f clusters/sockshop-useast.yaml
# Make some shortcuts for ease of use
export ASIA=$(kubectl config get-contexts -o name | grep sockshop-asia)
export EUROPE=$(kubectl config get-contexts -o name | grep sockshop-europe)
export USCENTRAL=$(kubectl config get-contexts -o name | grep sockshop-uscentral)
export USEAST=$(kubectl config get-contexts -o name | grep sockshop-useast)
# Run the initial Deployment
kubectl apply -f sockshop1.yaml
