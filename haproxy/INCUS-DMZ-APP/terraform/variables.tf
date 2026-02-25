variable "instance_name" {
  description = "Name of the Ubuntu VM"
  type        = string
  default     = "DMZ"
}

variable "cpu" {
  description = "Number of CPUs for the VM"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory size for the VM"
  type        = string
  default     = "2048MiB"
}
