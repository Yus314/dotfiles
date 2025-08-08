terraform {
  required_version = ">= 1.12"

  backend "s3" {
    bucket = "terraform-states"
    key    = "test/advanced-oci-compatibility.tfstate"
    region = "ap-tokyo-1"

    # OCI Object Storage最新版対応設定
    endpoint = "https://nr8pzcksrfds.compat.objectstorage.ap-tokyo-1.oraclecloud.com"

    # Customer Secret Key認証（ハードコード）
    access_key = "dbef9636bd287acf30ad6e6982acca905f8ca4a5"
    secret_key = "yJbJYqPxz8Fy1S3+FnlqWTr1Cjscq+DnFyEw+G02T+A="

    # Issue #34053対応: AWS SDK v2互換性設定
    force_path_style            = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    # Issue #36704対応: チェックサム無効化（最重要）
    skip_s3_checksum = true

    # 最新Terraform対応の実験的設定
    insecure = false

    # AWS SDK v2署名方式の明示的制御
    max_retries = 0
  }
}

# リソース定義
resource "null_resource" "advanced_test" {
  triggers = {
    timestamp = timestamp()
    test_mode = "advanced-oci-compatibility"
  }
}

output "advanced_test_result" {
  value = "Advanced OCI S3 compatibility test with Terraform v1.12.2"
}

output "configuration_summary" {
  value = {
    terraform_version  = "v1.12.2"
    oci_endpoint       = "https://nr8pzcksrfds.compat.objectstorage.ap-tokyo-1.oraclecloud.com"
    compatibility_mode = "aws-sdk-v2-workaround"
    issues_addressed   = ["#34053", "#36704"]
  }
}
