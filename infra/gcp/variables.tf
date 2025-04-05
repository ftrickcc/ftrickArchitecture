variable "project_id" {
  description = "El ID del proyecto GCP donde se desplegará la infraestructura"
  type        = string
}

variable "project_name" {
  description = "Nombre del proyecto que se usará como prefijo para los recursos"
  type        = string
  default     = "ftrickcc"
}

variable "region" {
  description = "Región de GCP para desplegar los recursos"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona dentro de la región seleccionada"
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "Tipo de máquina para los nodos de GKE"
  type        = string
  default     = "e2-medium"
}

variable "gke_num_nodes" {
  description = "Número de nodos en el clúster de GKE"
  type        = number
  default     = 1
}

variable "db_name" {
  description = "Nombre de la base de datos para Laravel"
  type        = string
  default     = "laravel"
}

variable "db_user" {
  description = "Usuario de la base de datos"
  type        = string
  default     = "laravel_user"
}

variable "db_password" {
  description = "Contraseña automática generada para la DB"
  type        = string
  sensitive   = true
  default     = ""  # Si se deja vacío, se generará una aleatoria
}

variable "ssh_source_ranges" {
  description = "Lista de rangos de IP permitidos para SSH"
  type        = list(string)
  default     = ["190.238.136.54/32"] # ¡Cambia esto por tus IPs!
}

variable "argocd_version" {
  default = "v2.10.4" # Coherente con tu templatefile()
}