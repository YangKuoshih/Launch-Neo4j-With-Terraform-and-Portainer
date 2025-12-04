variable "vpc_id" {
  description = "VPC ID (optional, will create new VPC if not provided)"
  type        = string
  default     = ""
}

variable "subnet_cidr" {
  description = "CIDR block for subnet"
  type        = string
  default     = "10.0.1.0/24"
}