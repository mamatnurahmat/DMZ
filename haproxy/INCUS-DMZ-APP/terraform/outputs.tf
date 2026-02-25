output "instance_name" {
  value = [incus_instance.dmz.name, incus_instance.app.name]
}

output "instance_ip" {
  value = [incus_instance.dmz.ipv4_address, incus_instance.app.ipv4_address]
}
