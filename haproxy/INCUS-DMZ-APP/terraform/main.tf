terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
    }
  }
}

provider "incus" {}

resource "incus_network" "incusbr0" {
  name = "incusbr0"
  type = "bridge"
  config = {
    "ipv4.address" = "10.0.0.1/24"
    "ipv4.nat"    = "true"
    "ipv6.address" = "none"
  }
}

resource "incus_instance" "dmz" {
  name  = "DMZ"
  image = "images:ubuntu/22.04/cloud"
  type  = "virtual-machine"
  config = {
    "limits.cpu"    = var.cpu
    "limits.memory" = var.memory
    "user.user-data" = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - openssh-server
      users:
        - name: ubuntu
          groups: [adm, sudo]
          shell: /bin/bash
          sudo: ALL=(ALL) NOPASSWD:ALL
          ssh_authorized_keys:
            - ${trimspace(file("~/.ssh/id_rsa.pub"))}
    EOF
  }
  device {
    name = "eth0"
    type = "nic"
    properties = {
      network        = incus_network.incusbr0.name
      "ipv4.address" = "10.0.0.10"
    }
  }
}

resource "incus_instance" "app" {
  name  = "APP"
  image = "images:ubuntu/22.04/cloud"
  type  = "virtual-machine"
  config = {
    "limits.cpu"    = var.cpu
    "limits.memory" = var.memory
    "user.user-data" = <<-EOF
      #cloud-config
      package_update: true
      packages:
        - openssh-server
      users:
        - name: ubuntu
          groups: [adm, sudo]
          shell: /bin/bash
          sudo: ALL=(ALL) NOPASSWD:ALL
          ssh_authorized_keys:
            - ${trimspace(file("~/.ssh/id_rsa.pub"))}
    EOF
  }
  device {
    name = "eth0"
    type = "nic"
    properties = {
      network        = incus_network.incusbr0.name
      "ipv4.address" = "10.0.0.11"
    }
  }
}
