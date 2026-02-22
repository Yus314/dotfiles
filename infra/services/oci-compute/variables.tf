# OCI認証（tf-wrapperから環境変数で設定）
variable "tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "OCI User OCID"
  type        = string
}

variable "fingerprint" {
  description = "OCI API Key Fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "Path to OCI API Private Key"
  type        = string
}

# リージョン設定
variable "region" {
  description = "OCI Region"
  type        = string
  default     = "ap-tokyo-1"
}

# インスタンス設定
variable "instance_display_name" {
  description = "Display name for the instance"
  type        = string
  default     = "a1-flex-free"
}

variable "instance_shape" {
  description = "Instance shape"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs"
  type        = number
  default     = 4
}

variable "instance_memory_gb" {
  description = "Memory in GB"
  type        = number
  default     = 24
}

# OSイメージ（Ubuntu固定）
variable "image_ocid" {
  description = "OS Image OCID (Ubuntu ARM, Always Free eligible)"
  type        = string
  default     = null
}

# SSH（自宅IPのみ許可）
variable "ssh_allowed_cidr" {
  description = "Home IP CIDR for SSH (e.g., 203.0.113.10/32)"
  type        = string
}

# ネットワーク
variable "vcn_cidr_block" {
  description = "VCN CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.1.0/24"
}

# Availability Domain ローテーション（Terraform側で順番に試す）
variable "availability_domain_order" {
  description = "AD order to try (e.g., [1,2,3])"
  type        = list(number)
  default     = [1, 2, 3]
}

variable "availability_domain_attempt" {
  description = "1-based index into availability_domain_order"
  type        = number
  default     = 1
}
