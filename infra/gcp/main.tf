terraform {
    required_version = "~> 1.5.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.13.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ------------------------------------------------------------------------------
# Configuración de Red
# ------------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  delete_default_routes_on_create = true
}

resource "google_compute_router" "router" {
  name    = "${var.project_name}-router"
  network = google_compute_network.vpc.name
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.project_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_name}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.0.0.0/24"

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# ------------------------------------------------------------------------------
# Firewall Rules
# ------------------------------------------------------------------------------
resource "google_compute_firewall" "allow-ssh" {
  name    = "${var.project_name}-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
}

resource "google_compute_firewall" "allow-http-https" {
  name    = "${var.project_name}-allow-http-https"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

# ------------------------------------------------------------------------------
# GKE Cluster
# ------------------------------------------------------------------------------
resource "google_service_account" "gke" {
  account_id   = "${var.project_name}-gke-sa"
  display_name = "GKE Service Account"
}

resource "google_project_iam_member" "gke_sa_roles" {
  for_each = toset([
    "roles/container.admin",
    "roles/storage.objectViewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke.email}"
}

resource "google_container_cluster" "primary" {
  name     = "${var.project_name}-gke"
  location = var.zone
  initial_node_count = 2
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  timeouts {
    create = "30m"
    update = "40m"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  node_config {
    service_account = google_service_account.gke.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

    release_channel {
    channel = "REGULAR"  # Actualizaciones automáticas
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"  # Mantenimiento en horario no crítico
    }
  }

  lifecycle {
    ignore_changes = [
      node_config[0].oauth_scopes  # Evita cambios no deseados
    ]
  }

  depends_on = [
    google_compute_router_nat.nat,
    google_project_iam_member.gke_sa_roles,
    google_service_networking_connection.vpc_connection
  ]
}



resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.project_name}-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = var.gke_num_nodes

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 30
    service_account = google_service_account.gke.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}

resource "time_sleep" "wait_argo" {
  depends_on = [google_container_cluster.primary]
  create_duration = "2m"
}

module "gke_auth" {
  source       = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  project_id   = var.project_id
  location     = var.zone
  cluster_name = google_container_cluster.primary.name
  use_private_endpoint = false
  depends_on = [time_sleep.wait_argo, google_container_cluster.primary]
  
}

# ------------------------------------------------------------------------------
# Configuración de Kubernetes/kubectl
# ------------------------------------------------------------------------------

# Datos necesarios para acceder al cluster GKE
data "google_client_config" "default" {}

# Configurar providers después de la creación del cluster
provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "kubectl" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  load_config_file       = false
}

# ------------------------------------------------------------------------------
# Argo CD con Kubectl
# ------------------------------------------------------------------------------

data "kubectl_file_documents" "namespace" {
    content = file("../k8s/argocd/namespace.yaml")
} 

data "kubectl_file_documents" "argocd" {
    content = file("../k8s/argocd/install.yaml")
}

data "kubectl_file_documents" "app-of-apps" {
    content = file("../k8s/argocd/app-of-apps.yaml")
}

resource "kubectl_manifest" "namespace" {
    count     = length(data.kubectl_file_documents.namespace.documents)
    yaml_body = element(data.kubectl_file_documents.namespace.documents, count.index)
    override_namespace = "argocd"
}

resource "kubectl_manifest" "argocd" {
    depends_on = [
      kubectl_manifest.namespace,
    ]
    count     = length(data.kubectl_file_documents.argocd.documents)
    yaml_body = element(data.kubectl_file_documents.argocd.documents, count.index)
    override_namespace = "argocd"
}

resource "kubectl_manifest" "app-of-apps" {
    depends_on = [
      kubectl_manifest.argocd,
    ]
    count     = length(data.kubectl_file_documents.app-of-apps.documents)
    yaml_body = element(data.kubectl_file_documents.app-of-apps.documents, count.index)
    override_namespace = "argocd"
}

# ------------------------------------------------------------------------------
# Datos para obtener la IP de Argo CD
# ------------------------------------------------------------------------------
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }
  depends_on = [kubectl_manifest.argocd]
}

# ------------------------------------------------------------------------------
# Cloud SQL
# ------------------------------------------------------------------------------
resource "google_service_networking_connection" "vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
  depends_on = [google_compute_router_nat.nat]
}

resource "google_compute_global_address" "private_ip_alloc" {
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}


resource "google_sql_database_instance" "instance" {
  name             = "${var.project_name}-mysql"
  database_version = "MYSQL_8_0"
  region           = var.region

  settings {
    tier = "db-g1-small"
    ip_configuration {
      private_network = google_compute_network.vpc.id
    }
  }

  depends_on = [google_service_networking_connection.vpc_connection]
}

resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.instance.name
  depends_on = [google_sql_database_instance.instance]
}
# ------------------------------------------------------------------------------
# Storage
# ------------------------------------------------------------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "storage" {
  name          = "${var.project_id}-storage-${random_id.bucket_suffix.hex}"
  location      = var.region
  force_destroy = true
}
