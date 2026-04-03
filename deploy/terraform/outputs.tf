output "cluster_endpoint" {
  value     = google_container_cluster.zanzipay.endpoint
  sensitive = true
}
output "cluster_name" {
  value = google_container_cluster.zanzipay.name
}
output "postgres_connection_name" {
  value = google_sql_database_instance.zanzipay_pg.connection_name
}
