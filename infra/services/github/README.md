# GitHub user-key Terraform stack

This stack owns only the `Yus314` account's SSH and GPG keys. Repository
settings and GitHub Actions secrets are owned by the standalone GitHub stack.
Authentication is supplied through the GitHub provider's standard
`GITHUB_TOKEN` environment variable; no secret file is read here.

## State split safety

The OCI backend key is `github/user-keys/terraform.tfstate`. The previous key,
`github/terraform.tfstate`, is shared with the standalone stack and **must not
be migrated or copied** into this backend. Do not use `init -migrate-state`.

The new backend must start empty. Before the first plan or apply:

1. Back up the shared state through the normal operational process.
2. Remove only this directory's stale `.terraform` working metadata.
3. Run a fresh `terraform init -reconfigure` and verify that Terraform reports
   `github/user-keys/terraform.tfstate` as the backend object key.
4. Obtain the existing SSH key numeric IDs (for example with
   `gh api user/keys`) and import every SSH resource into the new state:

   ```console
   terraform import github_user_ssh_key.default <mac_book-id>
   terraform import github_user_ssh_key.sub <lab_main-id>
   terraform import github_user_ssh_key.desktop <my_desktop-id>
   ```

5. Adopt `github_user_gpg_key.main` before planning or applying.

### GPG adoption blocker

GitHub provider 6.11.1 does not support importing `github_user_gpg_key`: the
GitHub API does not return the previously uploaded armored key. Consequently,
there is no safe ordinary `terraform import` command for the existing GPG key.
Do **not** plan or apply this stack until an operator has selected and reviewed
a non-destructive adoption procedure (for example, a provider-supported method
in a future version). Deleting/recreating the GitHub key or hand-editing state
is intentionally not prescribed here.

No backend initialization, migration, import, plan, or apply is performed as
part of this ownership split.

## Dependency lock

`.terraform.lock.hcl` is intentionally tracked for this root and was generated
with Terraform 1.15.8 for Linux amd64 and Darwin arm64. Regenerating the lock
does not authorize backend initialization or any infrastructure operation.
