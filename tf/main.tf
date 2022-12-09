# <------------------------------------------VM Instance Start----------------------------------------------------------------->

# Creating vm instance for windows
resource "google_compute_instance" "instance-demo-lab" {
  name         = "instance-demo-lab"
  zone         = "asia-east1-b"
  machine_type = "n1-standard-4"
  
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network = google_compute_network.network1.name
    subnetwork = google_compute_subnetwork.sub-network-test.name
    access_config {
    }
  }

   tags = ["http-server"]

# Adding startup script
metadata = {
    startup-script = <<-EOT
      #!/bin/bash
      sudo apt-get update && 
      sudo apt-get install apache2 -y && 
      echo '<!doctype html><html><body><h1>Hello from Terraform on Google Cloud!</h1></body></html>' | sudo tee /var/www/html/index.html
EOT
  } 
}

# Creating custom subnetwork 

resource "google_compute_subnetwork" "sub-network-test" {
  name          = "sub-network-test"
  ip_cidr_range = "10.10.10.0/24"
  region        = "asia-east1"
  network       = google_compute_network.network1.name
}

# Creating a network 
resource "google_compute_network" "network1" {
  name                    = "network1"
  auto_create_subnetworks = false
}


# Creating firewall rules for network 
resource "google_compute_firewall" "test-firewall" {
  name    = "test-firewall"
  network = google_compute_network.network1.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "8080"]
  }
  source_ranges = [
    "0.0.0.0/0"
  ]

  target_tags = ["http-server"]
}




#Creation of instance template
resource "google_compute_instance_template" "lb-backend-template" {
  name         = var.gcp_project_id
  machine_type = "e2-medium"

  disk {
    source_image = "debian-cloud/debian-11"
    disk_size_gb = 100
    boot         = true
  }

  network_interface {
    network = "default"
     access_config {
    }
  }

}

# <------------------------------------------VM Instance End----------------------------------------------------------------->
# <------------------------------------------Bigquery Start----------------------------------------------------------------->

# Create storage Bucket
resource "google_storage_bucket" "lab_bucket" {
  name                        = var.gcp_project_id
  location                    = "asia-east1"
  storage_class = "NEARLINE"
}
# Create storage Bucket object
resource "google_storage_bucket_object" "object" {
  name          = "hello.csv"
  source        = "resources/hello.csv"
  bucket        = google_storage_bucket.lab_bucket.name
}


# Bigquery dataset Creation 
resource "google_bigquery_dataset" "dataset" {
  dataset_id                  = var.dataset
  description                 = "This is a test description"
  location                    = "US"
}

resource "google_bigquery_job" "job_1" {
  job_id     = "job_load_1"

  labels = {
    "my_job" ="load_table_1"
  }

  load {
    source_uris = [
      "gs://${google_storage_bucket_object.object.bucket}/${google_storage_bucket_object.object.name}",
    ]

    destination_table {
      project_id = google_bigquery_table.table_1.project
      dataset_id = google_bigquery_table.table_1.dataset_id
      table_id   = google_bigquery_table.table_1.table_id
    }
  }
}


#Bigquery Table Creation

resource "google_bigquery_table" "table_1" {
  deletion_protection = false
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  table_id   = var.table_1

    schema = <<EOF
[
  
  {
    "name": "name",
    "type": "STRING",
    "mode": "REQUIRED"
  },
  {
    "name": "employee_id",
    "type": "INTEGER",
    "mode": "REQUIRED"
  },
  {
    "name": "address",
    "type": "STRING",
    "mode": "REQUIRED"
  }
]
EOF
}

# <------------------------------------------Bigquery end----------------------------------------------------------------->

# <------------------------------------------Load Balancer Start----------------------------------------------------------------->

# Creation of instance group
  resource "google_compute_instance_group_manager" "lb-backend-group" {
    name              = "lb-backend-group"
    zone              = var.gcp_zone
    project           = var.gcp_project_id

    base_instance_name = "lb-backend-group"

    version {
      instance_template  = google_compute_instance_template.lb-backend-template.id
    }

    target_size  = 2
  }


# Create a health check for the load balancer
  resource "google_compute_health_check" "http-basic-check" {
    name              = "http-basic-check"
    project           = var.gcp_project_id

    timeout_sec        = 1
    check_interval_sec = 1

    http_health_check {
      port = 80
      }

  }

# Set up a global static external IP address
  resource "google_compute_global_address" "lb-ipv4-1" {
    project       = var.gcp_project_id 
    name          = "lb-ipv4-1"
    ip_version    = "IPV4"

  }
  

  # Create a load balancer
  resource "google_compute_url_map" "urlmap" {
    project         = var.gcp_project_id
    name            = "web-map-http"
    default_service = google_compute_backend_service.web-backend-service.id
  }

# Create a backend service
  resource "google_compute_backend_service" "web-backend-service" {
    project       = var.gcp_project_id
    name          = "web-backend-service"
    health_checks = [google_compute_health_check.http-basic-check.id]
    protocol      = "HTTP"
    port_name     = "http"


    backend {
      group         = google_compute_instance_group_manager.lb-backend-group.instance_group
    }
  }

 # Create a global forwarding rule
  resource "google_compute_global_forwarding_rule" "http-content-rule" {
    project               = var.gcp_project_id
    name                  = "http-content-rule"
    ip_address            = google_compute_global_address.lb-ipv4-1.address
    target                = google_compute_target_http_proxy.http-lb-proxy.id
    port_range            = "80"

  }

  # Create a target HTTP proxy
  resource "google_compute_target_http_proxy" "http-lb-proxy" {
    project     = var.gcp_project_id
    name        = "http-lb-proxy"
    url_map     = google_compute_url_map.urlmap.id
  }

# <------------------------------------------Load Balancer End----------------------------------------------------------------->

# <------------------------------------------Cloud DNS Start----------------------------------------------------------------->

#Create Cloud DNS Basic-zone(Public)
resource "google_dns_managed_zone" "example-test" {
  name     = "example"
  dns_name    = "example-${random_id.rnd.hex}.com."
}

resource "random_id" "rnd" {
  byte_length = 4
}

resource "google_dns_record_set" "example" {
  managed_zone = google_dns_managed_zone.example-test.name

  name    = "www.${google_dns_managed_zone.example-test.dns_name}"
  type    = "A"
  rrdatas = [google_compute_instance.instance-demo-lab.network_interface[0].access_config[0].nat_ip]
  ttl     = 300
}

# <------------------------------------------Cloud DNS End----------------------------------------------------------------->
# <------------------------------------------Cloud Run Basic Start----------------------------------------------------------------->
# Creation of cloud run basic

resource "google_project_service" "run_api" {
  service = "run.googleapis.com"

  disable_on_destroy = true
}

resource "google_cloud_run_service" "default" {
  name     = "hello-server-run-service"
  location = "us-central1"

  template {
    spec {
      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
  depends_on = [google_project_service.run_api]
}
# <------------------------------------------Cloud Run Basic End----------------------------------------------------------------->
