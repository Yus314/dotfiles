# VM.Standard.A1.Flex Instance
resource "oci_core_instance" "a1_flex" {
  compartment_id      = local.selected_compartment
  availability_domain = local.selected_ad_name
  display_name        = var.instance_display_name
  shape               = var.instance_shape

  # Flexible Shape設定
  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  # ブートボリューム設定
  source_details {
    source_type             = "image"
    source_id               = local.selected_image_ocid
    boot_volume_size_in_gbs = 50 # デフォルト。合計200GB枠にカウント
  }

  # ネットワーク設定
  create_vnic_details {
    subnet_id                 = oci_core_subnet.main.id
    display_name              = "${var.instance_display_name}-vnic"
    assign_public_ip          = true
    assign_private_dns_record = true
    hostname_label            = "a1flex"
  }

  # メタデータ（SSH公開鍵）
  metadata = {
    ssh_authorized_keys = local.secrets.ssh_public_key
    user_data           = base64encode(file("${path.module}/cloud-init.yaml"))
  }

  # Always Free対象インスタンスのため、preemptibleは設定しない
  # preemptible_instance_config は設定しないこと

  lifecycle {
    # Out of Capacity エラー時にリトライするため
    # create_before_destroy は使用しない
    ignore_changes = [
      defined_tags,
      freeform_tags,
    ]
  }
}

# Instance VNIC (Public/Private IP取得用)
data "oci_core_vnic_attachments" "a1_flex" {
  compartment_id = local.selected_compartment
  instance_id    = oci_core_instance.a1_flex.id
}

data "oci_core_vnic" "a1_flex" {
  vnic_id = data.oci_core_vnic_attachments.a1_flex.vnic_attachments[0].vnic_id
}

# Reserved Public IP（オプション: 固定IP）
# 料金条件は公式ドキュメントで要確認
# resource "oci_core_public_ip" "reserved" {
#   compartment_id = local.selected_compartment
#   display_name   = "${var.instance_display_name}-ip"
#   lifetime       = "RESERVED"
# }
