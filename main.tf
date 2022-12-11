provider "google" {
    credentials = file("mygcp-creds.json")
    project = var.project
    region = var.region
    zone = var.zone
}

resource "google_compute_instance" "database" {
  name         = "database"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

    network_interface {
    network    = "default"
    stack_type = "IPV4_ONLY"
    network_ip = "10.186.0.5"
  }

    metadata = {
    startup-script = "#! /bin/bash\napt update\napt install docker.io -y\napt install docker-compose -y\nusermod -aG docker g249037\ntimedatectl set-timezone Europe/Warsaw\ngit clone https://github.com/wilkadam/gcp_talkyard\ncd gcp_talkyard\nsed -i 's/change_me/${var.postgres_pass}/g' .env\ndocker-compose -f docker-compose-rdb.yml up -d"
  }

}


resource "google_compute_instance_template" "talkyardtemplate" {

  disk {
    auto_delete  = true
    boot         = true
    device_name  = "talkyardgroup"
    disk_size_gb = 10
    disk_type    = "pd-balanced"
    mode         = "READ_WRITE"
    source_image = "projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-v20221018"
    type         = "PERSISTENT"
  }
  labels = {
    managed-by-cnrm = "true"
  }
  machine_type = "e2-medium"
  metadata = {
    startup-script = "#! /bin/bash\napt update\napt install docker.io -y\napt install docker-compose -y\nusermod -aG docker g249037\ncd /home/g249037\nsysctl -w vm.max_map_count=262144\nsysctl -p\ntimedatectl set-timezone Europe/Warsaw\ngit clone https://github.com/wilkadam/gcp_talkyard\ncd gcp_talkyard\nsed -i 's/change_me/${var.postgres_pass}/g' .env\ncd conf\nrandom=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 82 | head -n 1)\nsed -i 's|change_this|'$random'|g' play-framework.conf\nsed -i 's/SMTP_PASS/${var.smtp_password}/g' play-framework.conf\n sed -i 's/amazingdomain.online/${var.cloudflare_domain_name}/g' play-framework.conf\nsed -i 's/10.186.0.33/10.186.0.5/g' play-framework.conf\ncd ..\ndocker-compose up -d"
  }
  name = "talkyardtemplate"
  network_interface {
    network    = "https://www.googleapis.com/compute/v1/projects/${var.project}/global/networks/default"
    stack_type = "IPV4_ONLY"
  }
  project = var.project
  reservation_affinity {
    type = "ANY_RESERVATION"
  }
  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }

  tags = ["http-server"]
}


resource "google_compute_health_check" "health_check1" {
  check_interval_sec = 30
  healthy_threshold  = 2
  unhealthy_threshold = 5
  name               = "health-check1"
  timeout_sec        = 5
  

  tcp_health_check {
    port = "80"
  }

}

resource "google_compute_firewall" "fw_allow_health_check" {
  allow {
    ports    = ["80"]
    protocol = "tcp"
  }
  direction     = "INGRESS"
  name          = "fw-allow-health-check"
  network       = "https://www.googleapis.com/compute/v1/projects/${var.project}/global/networks/default"
  priority      = 1000
  project       = var.project
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["allow-health-check"]
}

resource "google_compute_firewall" "default_allow_http" {
  allow {
    ports    = ["80"]
    protocol = "tcp"
  }
  direction     = "INGRESS"
  name          = "default-allow-http"
  network       = "https://www.googleapis.com/compute/v1/projects/${var.project}/global/networks/default"
  priority      = 1000
  project       = var.project
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

resource "google_compute_target_pool" "example" {
  name          = "example-target-pool"
  #health_checks = ["${google_compute_http_health_check.health_check1.name}"]
}

resource "google_compute_instance_group_manager" "example" {
  name = "example-group-manager"
  zone = var.zone

  version {
    instance_template  = google_compute_instance_template.talkyardtemplate.id
  }

   named_port {
    name = "http"
    port = 80
  }

  target_pools       = ["${google_compute_target_pool.example.self_link}"]
  base_instance_name = "example"

  auto_healing_policies {
    health_check      = google_compute_health_check.health_check1.id
    initial_delay_sec = 60
 }
}

resource "google_compute_autoscaler" "example" {
  name   = "example-autoscaler"
  zone   = var.zone
  target = "${google_compute_instance_group_manager.example.self_link}"

    autoscaling_policy {
    max_replicas    = 2
    min_replicas    = 1
    cooldown_period = 150

    cpu_utilization {
      target = 0.7
  }
}
}

resource "google_compute_router" "router1" {
  name    = "my-router"
  region  = var.region
  network = "default"
}

module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 1.2"
  project_id = var.project
  region     = var.region
  router     = google_compute_router.router1.name
}

resource "google_compute_address" "lb_ipv4_1" {
  address_type = "EXTERNAL"
  name         = "lb-ipv4-1"
  network_tier = "PREMIUM"
  project      = var.project
  region       = var.region
}
#########################################

resource "google_compute_ssl_certificate" "this" {
  name_prefix = "${var.name}-ssl-"
  private_key = file("./certs/private.key")
  certificate = file("./certs/certificate.crt")

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_backend_service" "this" {
  name        = var.name
  port_name   = "http"
  protocol    = "HTTP"
  #timeout_sec = 10

  health_checks = ["https://www.googleapis.com/compute/v1/projects/${var.project}/global/healthChecks/health-check1"]

  backend {
   group                 = google_compute_instance_group_manager.example.instance_group
   balancing_mode        = "RATE"
   capacity_scaler       = 1.0
   max_rate_per_instance = 500
  }

  cdn_policy {
    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = true
    }
    cache_mode                   = "CACHE_ALL_STATIC"
    client_ttl                   = 3600
    default_ttl                  = 3600
    max_ttl                      = 86400
    signed_url_cache_max_age_sec = 0
  }
  connection_draining_timeout_sec = 300
  enable_cdn                      = true
  load_balancing_scheme           = "EXTERNAL"
  project                         = var.project
  session_affinity                = "NONE"
  timeout_sec                     = 30
 
}


resource "google_compute_global_address" "this" {
  name = "${var.name}-ipv4"
}

resource "google_compute_url_map" "http" {
  name = "${var.name}-http"

  default_url_redirect {
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
    https_redirect         = true
  }
}

resource "google_compute_target_http_proxy" "http" {
  name    = "${var.name}-http"
  url_map = google_compute_url_map.http.self_link
}

resource "google_compute_global_forwarding_rule" "http" {
  name       = "${var.name}-http"
  target     = google_compute_target_http_proxy.http.self_link
  ip_address = google_compute_global_address.this.address
  port_range = "80"
}

resource "google_compute_url_map" "https" {
  name            = "${var.name}-https"
  default_service = google_compute_backend_service.this.id
}

resource "google_compute_target_https_proxy" "https" {
  name             = "${var.name}-https"
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_ssl_certificate.this.id]
  }

resource "google_compute_global_forwarding_rule" "https" {
  name       = "${var.name}-https"
  target     = google_compute_target_https_proxy.https.id
  ip_address = google_compute_global_address.this.address
  port_range = "443"
}

output "Loadbalancer-IPv4-Address" {
   value = google_compute_global_address.this.address
}

#####CLOUDFLARE#####

terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "3.18"
    }
  }
}

provider "cloudflare" {
  email   = var.cloudflare_email
  api_token = var.cloudflare_api_token
}

data "cloudflare_zone" "this" {
  name = var.cloudflare_domain_name
}

resource "cloudflare_record" "wrocball" {
  zone_id = data.cloudflare_zone.this.id
  name    = var.cloudflare_domain_name
  value   = "${google_compute_global_address.this.address}"
  type    = "A"
  proxied = true
}
