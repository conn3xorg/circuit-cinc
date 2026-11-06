variable "port" {
  type    = number
  default = 2308
}

# CI sets these to install an older release first, then upgrades to the
# circuit's own pin by applying again without them.
variable "cinc_version" {
  type    = string
  default = null
}

variable "checksums" {
  type    = map(string)
  default = null
}

module "cinc" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  cinc_version = var.cinc_version
  checksums    = var.checksums

  repo_path = local.repo
  run_list  = ["recipe[hello]"]
  schedule  = "hourly"

  # Reading these from the steps below makes the converge wait for them, and
  # runs it again when the cookbook changes.
  converge_trigger = sha256(join("", [for f in conn3x_file.cookbook__files : f.content]))
}
