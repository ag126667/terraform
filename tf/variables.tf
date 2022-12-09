variable "gcp_project_id" {
  type        = string
  description = "The GCP project ID to create resources in."
}

# Default value passed in
variable "gcp_region" {
  type        = string
  description = "Region to create resources in."
}

# Default value passed in
variable "gcp_zone" {
  type        = string
  description = "Zone to create resources in."
}
# Default dataset name
variable "dataset" {
  type        = string
  default     = "terraform_dataset"
  description = "Dataset name"
}

variable "table_1" {
  type        = string
  default     = "employee" 
  description = "Table to be created"
}

variable "bucket_1" {
  type        = string
  default     = "hello-server-23432" 
  description = "Table to be created"
}
