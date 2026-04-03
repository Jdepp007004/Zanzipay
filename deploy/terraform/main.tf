terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_container_cluster" "zanzipay" {
  name     = var.cluster_name
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {}
}

resource "google_container_node_pool" "zanzipay_nodes" {
  name       = "zanzipay-pool"
  location   = var.region
  cluster    = google_container_cluster.zanzipay.name
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    labels       = { app = "zanzipay" }
  }

  autoscaling {
    min_node_count = 3
    max_node_count = 20
  }
}

resource "google_sql_database_instance" "zanzipay_pg" {
  name             = "zanzipay-postgres"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier = "db-n1-standard-4"
    backup_configuration {
      enabled = true
    }
  }
  deletion_protection = true
}

resource "google_sql_database" "zanzipay_db" {
  name     = "zanzipay"
  instance = google_sql_database_instance.zanzipay_pg.name
}
