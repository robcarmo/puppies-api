module "vpc" {
  source     = "./modules/vpc"
  project_id = var.project_id
  region     = var.region
}

module "gke" {
  source     = "./modules/gke"
  project_id = var.project_id
  region     = var.region
  network    = module.vpc.network_name
  subnetwork = module.vpc.subnetwork_name
}

module "cloudsql" {
  source     = "./modules/cloudsql"
  project_id = var.project_id
  region     = var.region
  network    = module.vpc.network_self_link
}

module "memorystore" {
  source     = "./modules/memorystore"
  project_id = var.project_id
  region     = var.region
  network    = module.vpc.network_self_link
}
