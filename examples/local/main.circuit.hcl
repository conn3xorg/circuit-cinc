locals {
  repo = "/var/lib/cinc/repo"

  # The smallest real cookbook: a recipe that writes a file.
  cookbook = {
    "metadata.rb"        = <<-EOT
      name "hello"
      version "0.1.0"
    EOT
    "recipes/default.rb" = <<-EOT
      file "/etc/hello-from-cinc" do
        content "Converged by Cinc Client in local mode.\n"
        mode "0644"
      end
    EOT
  }
}

# Puts the cookbook on the host. Your own might come from git, a package or
# rsync: the circuit only needs it under repo_path before the converge.
circuit "cookbook" {
  hosts = { box = "127.0.0.1" }

  ssh {
    user             = "root"
    port             = var.port
    private_key_file = "./id_ed25519"
    known_hosts_file = "./known_hosts"
  }

  step "dirs" {
    for_each = toset(["/var/lib/cinc", local.repo, "${local.repo}/cookbooks", "${local.repo}/cookbooks/hello", "${local.repo}/cookbooks/hello/recipes"])
    directory {
      path = item.value
    }
  }

  step "files" {
    for_each = local.cookbook
    file {
      path    = "${local.repo}/cookbooks/hello/${item.key}"
      content = item.value
    }
  }
}
