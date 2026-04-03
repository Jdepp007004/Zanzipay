variable "project_id" {
  description = "GCP Project ID"
  type        = string
}
variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}
variable "cluster_name" {
  description = "GKE Cluster name"
  type        = string
  default     = "zanzipay"
}
variable "node_count" {
  description = "Number of nodes per zone"
  type        = number
  default     = 3
}
variable "machine_type" {
  description = "Node machine type"
  type        = string
  default     = "n2-standard-4"
}
