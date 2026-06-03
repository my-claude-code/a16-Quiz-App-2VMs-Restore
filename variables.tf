variable "location" {
  description = "Azure region"
  type        = string
  default     = "West Europe"
}

variable "vm_size" {
  description = "Azure VM size for both VMs"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "github_repo" {
  description = "GitHub repo URL to clone the app from"
  type        = string
  default     = "https://github.com/my-claude-code/a11-Quiz-App-PostgreSQL.git"
}

variable "domain" {
  description = "Domain name for the app (must point to app VM public IP)"
  type        = string
  default     = "aztest.dnsabr.com"
}

variable "backup_file" {
  description = "Name of the backup file to restore from blob storage (e.g. quiz_backup_20260603_084210.sql)"
  type        = string
}
