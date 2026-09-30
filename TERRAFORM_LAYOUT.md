# Terraform module layout

This repository uses `modules/*` for reusable Terraform child modules and `environments/<environment>/*` for Terraform root modules.

Each environment directory is planned and applied independently. It may call shared modules and may also contain resources that exist only in that environment. If the same resource pattern is needed by multiple environments, move that reusable pattern into `modules/` and parameterize it.

Run Terraform from the selected environment directory, for example:

```sh
terraform -chdir=environments/staging plan
terraform -chdir=environments/production plan
```

The `.ores-infra.toml` file records the shared directory convention and provider-native locations. Provider-specific repository integrations are separate from Terraform local module resolution.

Keep environment values and Terraform state outside reusable child-module directories. When refactoring already-managed resources into modules, preserve their Terraform addresses with the appropriate migration mechanism.
