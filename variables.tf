variable "project" {
    type = string
    description = "Google Cloud Platform Project ID"
    default = "name" 
}

variable "region" {
    type = string
    description = "Infrastructure Region"
    default = "europe-central2"
}

variable "project_name" {
    type = string
    description = "Project Name"
    default = "my-test-project"
}

variable "zone" {
    type = string
    description = "Zone"
    default = "europe-central2-a"
}

variable "name" {
    type = string
    description = "The base name of resources"
    default = "talkyard"
}

variable "postgres_pass" {
    type = string
    description = "Postgresql password"
    default = "password"
}

variable "smtp_password" {
    type = string
    description = "SMTP_PASS"
    default = "smtp_pass"
}

variable "cloudflare_email" {
    type = string
    description = "Cloudflare token email"
    default = "email"
}

variable "cloudflare_api_token" {
    type = string
    description = "Cloudflare API token"
    default = "token"
}

variable "cloudflare_zone_id" {
    type = string
    description = "Cloudflare zone ID"
    default = "zone"
}

variable "cloudflare_domain_name" {
    type = string
    description = "Cloudflare domain name"
    default = "domain_name"
}