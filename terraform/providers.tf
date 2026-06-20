provider "alicloud" {
  region = var.region

  # Credentials are read from environment variables by default:
  #   ALICLOUD_ACCESS_KEY
  #   ALICLOUD_SECRET_KEY
  #   ALICLOUD_SECURITY_TOKEN (optional, for STS)
  #
  # Alternatively, configure a shared credentials file or RAM role.
  # Do not hardcode secrets in this repository.
}
