output "instance_id" {
  description = "Instance OCID"
  value       = oci_core_instance.a1_flex.id
}

output "instance_public_ip" {
  description = "Public IP address"
  value       = data.oci_core_vnic.a1_flex.public_ip_address
}

output "instance_private_ip" {
  description = "Private IP address"
  value       = data.oci_core_vnic.a1_flex.private_ip_address
}

output "instance_state" {
  description = "Instance state"
  value       = oci_core_instance.a1_flex.state
}

output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.main.id
}

output "subnet_id" {
  description = "Subnet OCID"
  value       = oci_core_subnet.main.id
}

output "ssh_command" {
  description = "SSH connection command"
  value       = "ssh ubuntu@${data.oci_core_vnic.a1_flex.public_ip_address}"
}

output "availability_domain" {
  description = "Availability Domain"
  value       = oci_core_instance.a1_flex.availability_domain
}
