provider "google" {
  project = var.service_project
  region = var.region
}

provider "google-beta" {
  project = var.service_project
  region = var.region
}

resource "google_service_account" "tf_sa" {
  account_id = var.gke_service_account
  project = var.service_project
}

data "google_project" "service_project" {
  project_id = var.service_project
}

data "google_iam_policy" "network_user" {
  binding {
    role = "roles/compute.networkUser"
    members = [
      "serviceAccount:service-${data.google_project.service_project.number}@container-engine-robot.iam.gserviceaccount.com",
      "serviceAccount:${data.google_project.service_project.number}@cloudservices.gserviceaccount.com",
    ]
  }
}

resource "google_compute_subnetwork_iam_policy" "subnet_iam" {
  depends_on = [
    google_compute_subnetwork.subnet-central-1]

  project     = var.host_project
  subnetwork  = google_compute_subnetwork.subnet-central-1.name
  policy_data = data.google_iam_policy.network_user.policy_data
}

resource "google_project_iam_binding" "service_agents" {
  project = var.service_project
  role    = "roles/container.hostServiceAgentUser"
  members = [
    "serviceAccount:service-${data.google_project.service_project.number}@container-engine-robot.iam.gserviceaccount.com"
  ]
}

resource "google_project_iam_binding" "security_admin" {
  project = var.host_project
  role    = "roles/compute.securityAdmin"
  members = [
    "serviceAccount:service-${data.google_project.service_project.number}@container-engine-robot.iam.gserviceaccount.com"
  ]
}

resource "google_project_iam_member" "project_viewer" {
  for_each = toset([var.service_project, var.host_project])
  project = each.value
  member  = "serviceAccount:${google_service_account.tf_sa.email}"
  role    = "roles/viewer"
}

resource "google_compute_network" "non-prod-vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  project                 = var.host_project
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "subnet-central-1" {
  name                     = var.subnet_name
  network                  = google_compute_network.non-prod-vpc.name
  project                  = var.host_project
  ip_cidr_range            = "10.128.0.0/16"
  region                   = var.region
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "172.16.0.0/20"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "172.18.0.0/20"
  }

  secondary_ip_range {
    range_name    = "gke-master"
    ip_cidr_range = "172.20.0.0/20"
  }
}

resource "google_container_cluster" "gke" {
  provider = google

  name       = var.cluster_name
  network    = google_compute_network.non-prod-vpc.self_link
  subnetwork = google_compute_subnetwork.subnet-central-1.self_link
  location   = var.region

  initial_node_count       = 1
  remove_default_node_pool = false

  cluster_autoscaling {
    enabled = false
  }

  node_config {
    service_account = google_service_account.tf_sa.email
    image_type = "COS_CONTAINERD"
    machine_type = "n1-standard-2"
    disk_size_gb = 100

  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  addons_config {
    network_policy_config {
      disabled = false
    }
  }

  workload_identity_config {
    workload_pool = "${var.service_project}.svc.id.goog"
  }

  lifecycle {
    ignore_changes = [
      node_config,
      remove_default_node_pool
    ]
  }

  enable_shielded_nodes = true

  timeouts {
    create = "15m"
    update = "10m"
    delete = "10m"
  }
}
