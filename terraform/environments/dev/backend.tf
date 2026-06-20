terraform {
  backend "oss" {
    bucket  = "campaign-center-tf-state-1"
    prefix  = "campaign-center-infra"
    key     = "terraform.tfstate"
    region  = "ap-southeast-1"
    encrypt = true

    # Optional tablestore endpoint for state locking:
    # tablestore_endpoint = "https://campaign-center-lock.ap-southeast-1.ots.aliyuncs.com"
  }
}
