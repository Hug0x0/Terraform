terraform {
  required_version = ">= 0.12.2"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 3.43.0"
    }
     kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.1"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.16"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "1.24.0"
    }
  }
}
variable "project_id" {
  description = "replace-{id}"
}

variable "region" {
  description = "us-central1"
}

provider "google" { 
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc" {
  name = "replace"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_id}-subnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"
}
data "archive_file" "source" {
    type        = "zip"
    source_dir  = "../src"
    output_path = "/tmp/function.zip"
}

resource "aci_trigger_scheduler" "myScheduler" {
  name  = "myScheduler"
  annotation  = "ms"
  description = "from terraform"
}

resource "google_storage_bucket_object" "zip" {
    source       = data.archive_file.source.output_path
    content_type = "application/zip"

    name         = "src-${data.archive_file.source.output_md5}.zip"
    bucket       = google_storage_bucket.function_bucket.name

    depends_on   = [
        google_storage_bucket.function_bucket,
        data.archive_file.source
    ]
}

resource "google_cloudfunctions_function" "function" {
    name                  = "function-trigger-on-gcs"
    runtime               = "python37"
    source_archive_bucket = google_storage_bucket.function_bucket.name
    source_archive_object = google_storage_bucket_object.zip.name
    entry_point           = "hello_gcs"
    event_trigger {
        event_type = "google.storage.object.finalize"
        resource   = "${var.project_id}-input"
    }
    depends_on = [
        google_storage_bucket.function_bucket,
        google_storage_bucket_object.zip
    ]
}

resource "google_container_cluster" "primary" {
  name = "${var.project_id}-gke"
  location = var.region
  remove_default_node_pool = true
  initial_node_count = 1

  network = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
}
 resource "google_container_node_pool" "primary_nodes" {
   name       = "${google_container_cluster.primary.name}-node-pool"
   location   = var.region
   cluster    = google_container_cluster.primary.name
   node_count = var.gke_num_nodes

   node_config {
     labels = {
       env = var.project_id
     }
     machine_type = "n1-standard-1"
     tags         = ["gke-node", "${var.project_id}-gke"]
     metadata = {
       disable-legacy-endpoints = "true"
    }
   }
 }







