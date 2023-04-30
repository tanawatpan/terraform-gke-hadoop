resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "hadoop/id_rsa"
  file_permission = "0600"

  lifecycle {
    replace_triggered_by = [
      tls_private_key.ssh.id
    ]
  }
}

resource "local_file" "public_key" {
  content         = trimspace(tls_private_key.ssh.public_key_openssh)
  filename        = "hadoop/id_rsa.pub"
  file_permission = "0644"

  lifecycle {
    replace_triggered_by = [
      tls_private_key.ssh.id,
      local_file.private_key.id
    ]
  }
}
