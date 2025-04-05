output "kubernetes_cluster_name" {
  description = "Nombre del clúster GKE"
  value       = google_container_cluster.primary.name
}

output "kubernetes_cluster_host" {
  description = "Host del clúster GKE"
  value       = "https://${google_container_cluster.primary.endpoint}"
}

output "project_id" {
  description = "ID del proyecto GCP"
  value       = var.project_id
}

output "region" {
  description = "Región GCP"
  value       = var.region
}

output "zone" {
  description = "Zona GCP"
  value       = var.zone
}

output "db_instance_name" {
  description = "Nombre de la instancia de Cloud SQL"
  value       = google_sql_database_instance.instance.name
}

output "db_connection_name" {
  description = "Nombre de conexión de la base de datos"
  value       = google_sql_database_instance.instance.connection_name
}

output "db_name" {
  description = "Nombre de la base de datos"
  value       = google_sql_database.database.name
}

output "storage_bucket_name" {
  description = "Nombre del bucket de almacenamiento"
  value       = google_storage_bucket.storage.name
}

output "gke_service_account" {
  description = "Email de la cuenta de servicio de GKE"
  value       = google_service_account.gke.email
}

output "argocd_ip" {
  value = data.kubernetes_service.argocd_server.status.0.load_balancer.0.ingress.0.ip
}

output "gke_endpoint" {
  value = google_container_cluster.primary.endpoint
}
output "argocd_endpoint" {
  value = "https://${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip}"
}