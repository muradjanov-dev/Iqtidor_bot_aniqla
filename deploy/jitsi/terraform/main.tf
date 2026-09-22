# Oracle Cloud "Always Free" (Ampere A1) ustida Jitsi Meet serveri.
#
#   terraform init
#   terraform apply
#
# VM yonishi bilan cloud-init setup.sh ni ishga tushiradi va Jitsi o'rnatiladi.

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[
    min(var.availability_domain_number - 1, length(data.oci_identity_availability_domains.ads.availability_domains) - 1)
  ].name

  use_letsencrypt = var.domain != ""

  setup_args = join(" ", compact([
    local.use_letsencrypt ? "--domain ${var.domain}" : "--no-letsencrypt",
    local.use_letsencrypt ? "--email ${var.email}" : "",
    var.enable_auth ? "--auth" : "",
  ]))
}

# Domen berilgan bo'lsa email ham kerak — noto'g'ri sozlamani applydan oldin tutamiz.
resource "terraform_data" "validate_letsencrypt" {
  lifecycle {
    precondition {
      condition     = var.domain == "" || var.email != ""
      error_message = "domain berilganda email ham kerak (Let's Encrypt uchun)."
    }
  }
}

# ------------------------------------------------------------------ tarmoq ---
resource "oci_core_vcn" "jitsi" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.instance_name}-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "jitsivcn"
}

resource "oci_core_internet_gateway" "jitsi" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.jitsi.id
  display_name   = "${var.instance_name}-igw"
  enabled        = true
}

resource "oci_core_route_table" "jitsi" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.jitsi.id
  display_name   = "${var.instance_name}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.jitsi.id
  }
}

resource "oci_core_security_list" "jitsi" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.jitsi.id
  display_name   = "${var.instance_name}-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH
  ingress_security_rules {
    source   = var.ssh_allowed_cidr
    protocol = "6"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # HTTP (Let's Encrypt tekshiruvi + HTTPS'ga yo'naltirish)
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 80
      max = 80
    }
  }

  # HTTPS (Jitsi web)
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # Videobridge — audio/video trafigi. Busiz ovoz/video ishlamaydi.
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "17"
    udp_options {
      min = 10000
      max = 10000
    }
  }

  # ICMP (ping/MTU)
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1"
  }
}

resource "oci_core_subnet" "jitsi" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.jitsi.id
  display_name               = "${var.instance_name}-subnet"
  cidr_block                 = "10.0.1.0/24"
  route_table_id             = oci_core_route_table.jitsi.id
  security_list_ids          = [oci_core_security_list.jitsi.id]
  dns_label                  = "jitsisubnet"
  prohibit_public_ip_on_vnic = false
}

# ------------------------------------------------------------------- obraz ---
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-22\\.04-aarch64-[0-9\\.-]+$"]
    regex  = true
  }
}

# ------------------------------------------------------------------ server ---
resource "oci_core_instance" "jitsi" {
  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.jitsi.id
    assign_public_ip = true
    hostname_label   = "jitsi"
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
    user_data = base64encode(templatefile("${path.module}/../cloud-init.yaml.tftpl", {
      setup_script_b64 = filebase64("${path.module}/../setup.sh")
      setup_args       = local.setup_args
    }))
  }

  # cloud-init user_data o'zgarsa serverni qaytadan yaratmaslik uchun:
  # o'zgarishni qo'lda qo'llash yaxshiroq (setup.sh ni SSH orqali qayta ishlating).
  lifecycle {
    ignore_changes = [metadata["user_data"]]
  }
}
