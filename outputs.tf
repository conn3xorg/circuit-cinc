output "service" {
  description = "systemd unit that runs one converge. Start it by hand with systemctl start, and read its log with journalctl -u."
  value       = "cinc-client.service"
}

output "client" {
  description = "Path of the client on each host."
  value       = local.client
}
