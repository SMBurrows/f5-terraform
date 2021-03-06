### VARIALES ###

# TAGS
variable application_dns  { default = "www.example.com" }  # ex. "www.example.com"
variable application      { default = "www"             }  # ex. "www" - short name used in object naming
variable environment      { default = "f5env"           }  # ex. dev/staging/prod
variable owner            { default = "f5owner"         }  
variable group            { default = "f5group"         }
variable costcenter       { default = "f5costcenter"    }  
variable purpose          { default = "public"          }  

# PLACEMENT
variable region     { default = "us-west1"   }
variable zone       { default = "us-west1-a" }
variable network    {}
variable subnet_id  {}

# SYSTEM
variable instance_name        { default = "f5vm01"  }
variable dns_server           { default = "8.8.8.8" }
variable ntp_server           { default = "0.us.pool.ntp.org" }
variable timezone             { default = "UTC" }
variable management_gui_port  { default = "8443" }

# PROXY:
variable instance_type  { default = "n1-standard-1" }
variable image_name     { default = "f5-7626-networks-public/f5-byol-bigip-13-0-0-2-3-1671-best" }

# SECURITY
variable ssh_key_public    {}  # string of key ex. "ssh-rsa AAAA..."
variable restricted_src_address     { default = "0.0.0.0/0" }

variable admin_username {}
variable admin_password {}

# NOTE certs not used below but keeping as optional input in case need to extend
variable site_ssl_cert  { default = "not-required-if-terminated-on-lb" }
variable site_ssl_key   { default = "not-required-if-terminated-on-lb" }

# APPLICATION
variable vs_dns_name         { default = "www.example.com" }
variable vs_address          { default = "0.0.0.0" }
variable vs_mask             { default = "0.0.0.0" }
variable vs_port             { default = "443" }
variable pool_address        { default = "10.0.3.4" }
variable pool_member_port    { default = "80" }
variable pool_name           { default = "www.example.com" }  # DNS (ex. "www.example.com") used to create fqdn node if there's no Service Discovery iApp 

# LICENSE
variable license_key {}


### RESOURCES ###

# NOTE: Get creds from environment variables
provider "google" {
}

resource "google_compute_firewall" "sg" {
  name    = "${var.environment}-proxy-firewall"
  network = "${var.network}"

  allow {
    protocol = "tcp"
    ports    = [ "80", "${var.vs_port}" ]
  }

  source_ranges = [ "0.0.0.0/0" ]
}

resource "google_compute_firewall" "sg_management" {
  name    = "${var.environment}-proxy-management-firewall"
  network = "${var.network}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = [ "22", "${var.management_gui_port}" ]
  }

  source_ranges = ["${var.restricted_src_address}"]
}


data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.tpl")}"

  vars {
    admin_username        = "${var.admin_username}"
    admin_password        = "${var.admin_password}"
    management_gui_port   = "${var.management_gui_port}"
    dns_server            = "${var.dns_server}"
    ntp_server            = "${var.ntp_server}"
    timezone              = "${var.timezone}"
    region                = "${var.region}"
    application           = "${var.application}"
    vs_dns_name           = "${var.vs_dns_name}"
    vs_address            = "${var.vs_address}"
    vs_mask               = "${var.vs_mask}"
    vs_port               = "${var.vs_port}"
    pool_name             = "${var.pool_name}"
    pool_address          = "${var.pool_address}"
    pool_member_port      = "${var.pool_member_port}"
    site_ssl_cert         = "${var.site_ssl_cert}"
    site_ssl_key          = "${var.site_ssl_key}"
    license_key           = "${var.license_key}"
  }
}

resource "google_compute_instance" "bigip" {
    name = "${var.environment}-${var.instance_name}"
    machine_type = "${var.instance_type}"
    zone = "${var.zone}"
    disk {
        image = "${var.image_name}"
    }
    disk {
        type = "local-ssd"
        scratch = true
    }
    network_interface {
        subnetwork = "${var.subnet_id}"
        access_config {
        }
    }
    can_ip_forward = "true"
    service_account {
        scopes = ["userinfo-email", "compute-ro", "storage-ro"]
    }
    # Shows up as network tags
    # Must be a match of regex '(?:[a-z](?:[-a-z0-9]{0,61}[a-z0-9])?)
    tags = [
        "name-${var.environment}-shared-proxy",
        "environment-${var.environment}",
        "owner-${var.owner}",
        "group-${var.group}",
        "costcenter-${var.costcenter}",
        "application-${var.application}"
    ]
    metadata {
        Name           = "${var.environment}_proxy"
        environment    = "${var.environment}"
        owner          = "${var.owner}"
        group          = "${var.group}"
        costcenter     = "${var.costcenter}"
        application    = "${var.application}"
        ssh-keys       = "${var.admin_username}:${var.ssh_key_public}"
    }
    metadata_startup_script = "${data.template_file.user_data.rendered}"
}


output "sg_id" { value = "${google_compute_firewall.sg.self_link}" }
output "sg_name" { value = "${var.environment}-proxy-firewall}" }

output "instance_id" { value = "${google_compute_instance.bigip.self_link}"  }
output "instance_private_ip" { value = "${google_compute_instance.bigip.network_interface.0.address}" }
output "instance_public_ip" { value = "${google_compute_instance.bigip.network_interface.0.access_config.0.assigned_nat_ip}" }



