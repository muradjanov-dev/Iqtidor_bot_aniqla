# --- Oracle Cloud API kalitlari (Console -> Profile -> API Keys) -------------
variable "tenancy_ocid" {
  description = "Tenancy OCID (ocid1.tenancy.oc1..)"
  type        = string
}

variable "user_ocid" {
  description = "User OCID (ocid1.user.oc1..)"
  type        = string
}

variable "fingerprint" {
  description = "API kalit fingerprint'i (aa:bb:cc:...)"
  type        = string
}

variable "private_key_path" {
  description = "API private key fayli (~/.oci/oci_api_key.pem)"
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment OCID. Odatda tenancy_ocid bilan bir xil (root compartment)."
  type        = string
}

variable "region" {
  description = "Oracle region, masalan eu-frankfurt-1 yoki me-dubai-1"
  type        = string
  default     = "eu-frankfurt-1"
}

# --- Server ------------------------------------------------------------------
variable "instance_name" {
  description = "VM nomi"
  type        = string
  default     = "jitsi-meet"
}

variable "availability_domain_number" {
  description = <<-EOT
    Qaysi Availability Domain'da yaratilsin (1, 2, 3).
    "Out of host capacity" xatosi chiqsa boshqa raqamni sinab ko'ring.
  EOT
  type        = number
  default     = 1
}

variable "ocpus" {
  description = "Ampere A1 yadrolar soni. Always Free limiti: jami 4."
  type        = number
  default     = 4
}

variable "memory_in_gbs" {
  description = "RAM (GB). Always Free limiti: jami 24."
  type        = number
  default     = 24
}

variable "boot_volume_size_in_gbs" {
  description = "Disk hajmi (GB). Always Free limiti: jami 200."
  type        = number
  default     = 60
}

variable "ssh_public_key_path" {
  description = "SSH public key fayli (~/.ssh/id_rsa.pub)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_allowed_cidr" {
  description = "SSH (22-port) kimga ochiq bo'lsin. Xavfsizroq: \"SIZNING.IP.MANZILINGIZ/32\"."
  type        = string
  default     = "0.0.0.0/0"
}

# --- Jitsi -------------------------------------------------------------------
variable "domain" {
  description = "Jitsi domeni, masalan meet.example.com yoki maktab.duckdns.org. Bo'sh bo'lsa self-signed sertifikat ishlatiladi."
  type        = string
  default     = ""
}

variable "email" {
  description = "Let's Encrypt uchun email. domain berilganda majburiy."
  type        = string
  default     = ""
}

variable "enable_auth" {
  description = "true bo'lsa faqat ro'yxatdan o'tgan foydalanuvchi xona ocha oladi (o'quvchilar mehmon)."
  type        = bool
  default     = false
}
