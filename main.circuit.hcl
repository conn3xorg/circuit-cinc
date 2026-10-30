# Facts give each host's distribution and architecture, which pick the package.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = contains(keys(var.checksums), "${contains(["rocky", "almalinux", "rhel"], self.os_id) ? "el/${split(".", self.os_version)[0]}" : "${self.os_id}/${self.os_version}"}/${self.arch}")
      error_message = "Host ${each.key} runs ${self.os_id} ${self.os_version} on ${self.arch}. This circuit has Cinc packages for ${join(", ", sort(keys(var.checksums)))}, and Cinc publishes none for Fedora."
    }
  }
}

locals {
  # Cinc publishes one build per Enterprise Linux major version, under "el".
  # Fedora's os_family is also redhat, so this can't go by family.
  platform = { for name, f in data.conn3x_host.facts : name => contains(["rocky", "almalinux", "rhel"], f.os_id) ? "el/${split(".", f.os_version)[0]}" : "${f.os_id}/${f.os_version}" }

  deb_arch = { x86_64 = "amd64", aarch64 = "arm64" }
  package = { for name, f in data.conn3x_host.facts : name => f.os_family == "debian" ?
    "cinc_${var.cinc_version}-1_${local.deb_arch[f.arch]}.deb" :
    "cinc-${var.cinc_version}-1.el${split(".", f.os_version)[0]}.${f.arch}.rpm"
  }

  cache_dir = "/var/cache/conn3x-cinc"
  client    = "/opt/cinc/bin/cinc-client"
  config    = "/etc/cinc/client.rb"
  unit_path = "/etc/systemd/system/cinc-client"

  # node_name is set because Ohai works out the name from the hostname command,
  # which minimal images lack. node_path keeps the record of each converge out
  # of repo_path, which may well be a Git checkout.
  config_content = { for name in keys(var.hosts) : name => <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    local_mode true
    chef_repo_path "${var.repo_path}"
    node_path "/var/lib/cinc/nodes"
    node_name "${replace(name, "/[^a-zA-Z0-9_.-]/", "-")}"
  EOT
  }

  # A run list given on the command line isn't saved with the node, so taking
  # a recipe out of run_list takes it out of the next converge.
  service_content = <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    [Unit]
    Description=Converge this host with Cinc Client in local mode
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    Environment=HOME=/root
    WorkingDirectory=${var.repo_path}
    ExecStart=${local.client} --local-mode --config ${local.config} --override-runlist ${join(",", var.run_list)}
  EOT

  timer_content = <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    [Unit]
    Description=Converge this host with Cinc Client on a schedule

    [Timer]
    OnCalendar=${coalesce(var.schedule, "hourly")}
    # A converge missed while the host was off runs when it comes back.
    Persistent=true

    [Install]
    WantedBy=timers.target
  EOT
}

circuit "cinc" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "curl" {
    package {
      name = "curl"
    }
  }

  step "cache_dir" {
    directory {
      path = local.cache_dir
    }
  }

  step "download" {
    download {
      url    = "https://packages.cinc.sh/files/stable/cinc/${var.cinc_version}/${local.platform[each.key]}/${local.package[each.key]}"
      sha256 = var.checksums["${local.platform[each.key]}/${data.conn3x_host.facts[each.key].arch}"]
      dest   = "${local.cache_dir}/${local.package[each.key]}"
    }
  }

  # Goes straight to dpkg and rpm: the package has its own Ruby and no
  # dependencies to fetch, and --oldpackage lets cinc_version go down as well
  # as up.
  step "install" {
    command {
      command = data.conn3x_host.facts[each.key].os_family == "debian" ? "dpkg -i ${local.cache_dir}/${local.package[each.key]}" : "rpm -U --oldpackage ${local.cache_dir}/${local.package[each.key]}"
      unless  = data.conn3x_host.facts[each.key].os_family == "debian" ? "[ \"$(dpkg-query -W -f '$${Version}' cinc 2>/dev/null)\" = ${var.cinc_version}-1 ]" : "[ \"$(rpm -q --qf '%%{VERSION}' cinc 2>/dev/null)\" = ${var.cinc_version} ]"
    }
  }

  step "config_dir" {
    directory {
      path = dirname(local.config)
    }
  }

  step "config" {
    file {
      path    = local.config
      content = local.config_content[each.key]
    }
  }

  step "service" {
    for_each = length(var.run_list) > 0 ? toset(["service"]) : toset([])
    file {
      path      = "${local.unit_path}.service"
      content   = local.service_content
      on_remove = "delete"
    }
  }

  step "timer_file" {
    for_each = var.schedule != null ? toset(["timer"]) : toset([])
    file {
      path      = "${local.unit_path}.timer"
      content   = local.timer_content
      on_remove = "delete"
    }
  }

  step "reload" {
    command {
      command = "systemctl daemon-reload"
      triggers = {
        service = length(var.run_list) > 0 ? sha256(local.service_content) : ""
        timer   = var.schedule != null ? sha256(local.timer_content) : ""
      }
    }
  }

  step "timer" {
    for_each = var.schedule != null ? toset(["timer"]) : toset([])
    service {
      name      = "cinc-client.timer"
      state     = "started"
      enabled   = true
      on_remove = "delete"
    }
  }

  # systemctl waits for a oneshot unit to finish and fails if it fails, so a
  # failed converge fails the apply, with the detail in the journal.
  step "converge" {
    for_each = length(var.run_list) > 0 ? toset(["converge"]) : toset([])
    command {
      command = "systemctl start cinc-client.service"
      triggers = {
        version = var.cinc_version
        config  = sha256(local.config_content[each.key])
        service = sha256(local.service_content)
        trigger = var.converge_trigger
      }
    }
  }
}
