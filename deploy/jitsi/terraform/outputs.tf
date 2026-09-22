output "public_ip" {
  description = "Serverning public IP manzili"
  value       = oci_core_instance.jitsi.public_ip
}

output "ssh_command" {
  description = "Serverga ulanish"
  value       = "ssh ubuntu@${oci_core_instance.jitsi.public_ip}"
}

output "dns_record" {
  description = "Domeningiz uchun yaratilishi kerak bo'lgan DNS yozuvi"
  value = var.domain != "" ? "A  ${var.domain}  ->  ${oci_core_instance.jitsi.public_ip}" : "(domen berilmagan)"
}

output "jitsi_url" {
  description = "Jitsi manzili (o'rnatish 5-10 daqiqa davom etadi)"
  value       = var.domain != "" ? "https://${var.domain}" : "https://${oci_core_instance.jitsi.public_ip}"
}

output "setup_log" {
  description = "O'rnatish jarayonini kuzatish"
  value       = "ssh ubuntu@${oci_core_instance.jitsi.public_ip} 'sudo tail -f /var/log/jitsi-setup.log'"
}
