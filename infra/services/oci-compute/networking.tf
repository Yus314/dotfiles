# Virtual Cloud Network
resource "oci_core_vcn" "main" {
  compartment_id = local.selected_compartment
  cidr_blocks    = [var.vcn_cidr_block]
  display_name   = "a1-flex-vcn"
  dns_label      = "a1flexvcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "main" {
  compartment_id = local.selected_compartment
  vcn_id         = oci_core_vcn.main.id
  display_name   = "a1-flex-igw"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "main" {
  compartment_id = local.selected_compartment
  vcn_id         = oci_core_vcn.main.id
  display_name   = "a1-flex-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# Security List
resource "oci_core_security_list" "main" {
  compartment_id = local.selected_compartment
  vcn_id         = oci_core_vcn.main.id
  display_name   = "a1-flex-sl"

  # Egress: Allow all outbound
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # Ingress: SSH (port 22)
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = var.ssh_allowed_cidr
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Ingress: ICMP (ping)
  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = "0.0.0.0/0"
    stateless = false
    icmp_options {
      type = 3
      code = 4
    }
  }

  # Ingress: HTTP (port 80) - optional
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 80
      max = 80
    }
  }

  # Ingress: HTTPS (port 443) - optional
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 443
      max = 443
    }
  }
}

# Subnet
resource "oci_core_subnet" "main" {
  compartment_id             = local.selected_compartment
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.subnet_cidr_block
  display_name               = "a1-flex-subnet"
  dns_label                  = "a1flexsubnet"
  route_table_id             = oci_core_route_table.main.id
  security_list_ids          = [oci_core_security_list.main.id]
  prohibit_public_ip_on_vnic = false

  # ADはTerraform側で順番に切り替える
  availability_domain = local.selected_ad_name
}
