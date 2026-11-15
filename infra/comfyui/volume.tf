# the shared network volume from infra/persistence (apply that first).
# path.module keeps the path right under `tofu -chdir=...`
data "terraform_remote_state" "persistence" {
  backend = "local"
  config = {
    path = "${path.module}/../persistence/terraform.tfstate"
  }
}
