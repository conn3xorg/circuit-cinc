variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "cinc_version" {
  type        = string
  default     = "19.4.46"
  description = "Cinc Client release to install, from https://omnitruck.cinc.sh/stable/cinc/versions/all."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cinc_version))
    error_message = "cinc_version is a version such as \"19.4.46\"."
  }
}

variable "checksums" {
  type        = map(string)
  description = "SHA-256 of the package for each platform, by \"PLATFORM/VERSION/ARCH\". Change these with cinc_version."
  default = {
    "ubuntu/24.04/x86_64"  = "71dd1056fc86b29b94d95798d087df8ad081670d070f01dbc38a87e9f8e02a22"
    "ubuntu/24.04/aarch64" = "28ea28866aacbac77fdca0b3550c6700225624d345592cddbeb6b1b929a2b107"
    "debian/13/x86_64"     = "83ad6e1b905a348909e1f312bc4f2f5061c566469a4ec77b041746378975d2a9"
    "debian/13/aarch64"    = "9954f9ec268db2748e8a33c955d20b492c7278ee3325cd5d33e135dce87d6ea8"
    "el/10/x86_64"         = "7d02410e28c23ebdf2eff1ef130ba9bf3383a1282b952c1f36a0a7594b087573"
    "el/10/aarch64"        = "b63b6dbc4cff4c00cd43bc9723b2ff365499a863b1c1caf41527e69db06c9252"
  }

  validation {
    condition     = alltrue([for k, c in var.checksums : can(regex("^(ubuntu|debian|el)/[0-9.]+/(x86_64|aarch64)$", k)) && can(regex("^[0-9a-f]{64}$", c))])
    error_message = "checksums maps a key such as \"debian/13/x86_64\" to a SHA-256 in lowercase hex."
  }
}

variable "repo_path" {
  type        = string
  default     = "/var/lib/cinc/repo"
  description = "Directory on the host that holds cookbooks/, and roles/ if you use them. Whatever can write here can run anything as root, so keep it writable by root alone."

  validation {
    condition     = can(regex("^/[a-zA-Z0-9/_.-]*[^/]$", var.repo_path))
    error_message = "repo_path must be an absolute path without a trailing slash."
  }
}

variable "run_list" {
  type        = list(string)
  default     = []
  description = "What to converge, such as [\"recipe[nginx]\", \"role[web]\"]. When empty, the circuit only installs the client."

  validation {
    condition     = alltrue([for r in var.run_list : can(regex("^(recipe|role)\\[[a-zA-Z0-9_.:@-]+\\]$", r))])
    error_message = "Each of run_list is recipe[NAME] or role[NAME], such as \"recipe[nginx::default]\"."
  }
}

variable "schedule" {
  type        = string
  default     = null
  description = "systemd OnCalendar expression that converges on a timer, such as \"hourly\" or \"*:0/30\". When null, there is no timer."

  validation {
    condition     = var.schedule == null || (can(regex("^[a-zA-Z0-9 *:/.,~-]+$", coalesce(var.schedule, "-"))) && length(var.run_list) > 0)
    error_message = "schedule is an OnCalendar expression, such as \"hourly\", and needs a run_list to run."
  }
}

variable "converge_trigger" {
  type        = string
  default     = ""
  description = "Any string, such as a cookbook's hash or a Git commit. Changing it converges on the next apply, for when something the circuit can't see has changed."
}
