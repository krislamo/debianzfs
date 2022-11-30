# Set 'password' using shell var: PKR_VAR_password=$(pwgen -s 8 1)
variable "password" {}

source "qemu" "bullseye-live" {
  iso_url           = "https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/debian-live-11.5.0-amd64-standard.iso"
  iso_checksum      = "sha256:8172b188061d098080bb315972becbe9bd387c856866746cee018102cd00fc9b"
  output_directory  = "output"
  shutdown_command  = "echo 'packer' | sudo -S shutdown -P now"
  disk_size         = "5000M"
  memory            = 2048
  format            = "qcow2"
  accelerator       = "kvm"
  http_directory    = "."
  ssh_username      = "user"
  ssh_password      = var.password
  ssh_timeout       = "5m"
  vm_name           = "debianzfs.qcow2"
  net_device        = "virtio-net"
  disk_interface    = "virtio"
  boot_wait         = "5s"
  boot_command      = [
        "<enter><wait10>",
        "<enter><wait>",
        "sudo -i<enter><wait>",
        "read -s userpw<enter><wait>",
        "${var.password}<enter><wait>",
        "PASSWORD=$(echo $userpw | openssl passwd -1 -stdin)<enter><wait>",
        "usermod -p \"$PASSWORD\" user<enter><wait>",
        "apt-get update && apt-get install -y ssh && \\<enter>",
        "systemctl start ssh && exit<enter>"
  ]
}

build {
  name = "zfs"
  sources = ["source.qemu.bullseye-live"]

  provisioner "file" {
    source      = "debianzfs.sh"
    destination = "/tmp/debianzfs.sh"
  }

  provisioner "shell" {
    scripts = ["scripts/setup.sh"]
  }

  provisioner "shell" {
     inline = ["sudo /tmp/debianzfs.sh -i -s0 -p changeme -P letmeinzfs! /dev/vda debianzfs"]
  }

}
