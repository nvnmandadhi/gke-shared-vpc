module "gke" {
  source = "../gke-shared-vpc/modules/gke"
  cluster_name = "gke-test"
  gke_service_account = "terraform"
  host_project = "<HOST_PROJECT>"
  region = "us-central1"
  service_project = "<SERVICE_PROJECT>"
  subnet_name = "subnet-central-1"
  vpc_name = "vpc-central1"
}