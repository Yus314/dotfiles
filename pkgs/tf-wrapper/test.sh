#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wrapper="$script_dir/tf-wrapper.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

config_dir="$tmp_dir/config"
bin_dir="$tmp_dir/bin"
mkdir -p "$config_dir" "$bin_dir"

for entry in \
  'tenancy.txt:ocid1.tenancy.test' \
  'user.txt:ocid1.user.test' \
  'fingerprint.txt:00:11:22' \
  'backend-bucket.txt:test-bucket' \
  'backend-namespace.txt:test-namespace' \
  'backend-region.txt:test-region'; do
  printf '%s\n' "${entry#*:}" >"$config_dir/${entry%%:*}"
done
printf '%s\n' 'test private key' >"$config_dir/private_key.pem"

cat >"$bin_dir/terraform" <<'EOF'
#!/usr/bin/env bash
printf 'terraform-called:%s\n' "$*"
printf 'tf-var-key:%s\n' "${TF_VAR_key:-<unset>}"
EOF
cat >"$bin_dir/yq" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
chmod +x "$bin_dir/terraform" "$bin_dir/yq"

error_output="$({
  cd "$tmp_dir"
  PATH="$bin_dir:$PATH" \
    TF_LOG_LEVEL=ERROR \
    TF_VAR_key=explicit-input-key \
    TF_WRAPPER_CONFIG_DIR_OVERRIDE="$config_dir" \
    bash "$wrapper" validate
} 2>&1)"

grep -q '^terraform-called:validate$' <<<"$error_output"
grep -q '^tf-var-key:explicit-input-key$' <<<"$error_output"
if grep -q 'INFO:' <<<"$error_output"; then
  printf 'ERROR: INFO output was not suppressed at TF_LOG_LEVEL=ERROR\n' >&2
  exit 1
fi

info_output="$({
  cd "$tmp_dir"
  PATH="$bin_dir:$PATH" \
    TF_VAR_key=explicit-input-key \
    TF_WRAPPER_CONFIG_DIR_OVERRIDE="$config_dir" \
    bash "$wrapper" validate
} 2>&1)"

grep -q 'TF_VAR_key (Terraform input only; backend key is configured separately):' <<<"$info_output"
if grep -q 'Backend Key:' <<<"$info_output"; then
  printf 'ERROR: wrapper still claims that TF_VAR_key is the effective backend key\n' >&2
  exit 1
fi

printf 'PASS: TF_LOG_LEVEL=ERROR reaches Terraform and suppresses INFO logs\n'
printf 'PASS: TF_VAR_key is passed to Terraform as an input variable\n'
printf 'PASS: key logging identifies TF_VAR_key as input-only, not backend config\n'
