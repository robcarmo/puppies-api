resource "google_redis_instance" "cache" {
  name           = "puppies-cache"
  memory_size_gb = 1
  region         = var.region

  authorized_network = var.network
}
