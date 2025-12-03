resource "google_sql_database_instance" "master" {
  name             = "puppies-db-instance"
  database_version = "POSTGRES_14"
  region           = var.region

  settings {
    tier = "db-f1-micro"
    
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network
    }
  }
  deletion_protection  = "false" # For demo purposes
}

resource "google_sql_database" "database" {
  name     = "puppies"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_user" "users" {
  name     = "puppies-user"
  instance = google_sql_database_instance.master.name
  password = "changeme"
}
