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

variable "aws_profile" {
  description = "AWS profile to use (for SSO or named profiles). Set to empty string to use default credential chain."
  type        = string
  default     = ""
}