output "app_public_ip" {
  description = "Public IP of the app VM — point your domain DNS here"
  value       = azurerm_public_ip.app.ip_address
}

output "db_public_ip" {
  description = "Public IP of the DB VM — for SSH only"
  value       = azurerm_public_ip.db.ip_address
}

output "app_url" {
  description = "Quiz app URL"
  value       = "https://${var.domain}"
}

output "ssh_app" {
  description = "SSH command for the app VM"
  value       = "ssh ivansto@${azurerm_public_ip.app.ip_address}"
}

output "ssh_db" {
  description = "SSH command for the DB VM"
  value       = "ssh ivansto@${azurerm_public_ip.db.ip_address}"
}

output "entra_redirect_uri" {
  description = "Add this to your Entra app registration under Authentication > Redirect URIs"
  value       = "https://${var.domain}/auth/callback"
}

output "ACTION_REQUIRED" {
  description = "Steps after deployment"
  value       = <<-EOT
    1. Point DNS IMMEDIATELY after deploy:
       Create A record: ${var.domain} → ${azurerm_public_ip.app.ip_address}

    2. Add redirect URI to Entra app registration:
       https://${var.domain}/auth/callback

    3. Monitor DB VM setup (installs PostgreSQL, downloads and restores backup):
       ssh ivansto@${azurerm_public_ip.db.ip_address} 'tail -f /var/log/db-setup.log'

    4. Monitor app VM setup (waits for DB, pulls TLS cert, starts app):
       ssh ivansto@${azurerm_public_ip.app.ip_address} 'tail -f /var/log/app-setup.log'

    No question imports needed — all data is restored from: ${var.backup_file}
  EOT
}
