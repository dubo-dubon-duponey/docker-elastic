variable "REGISTRY" {
  default = "docker.io"
}

target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Elastic"
    BUILD_DESCRIPTION = "A dubo image for Elastic"
  }
  tags = [
    "${REGISTRY}/dubodubonduponey/elastic",
  ]
  platforms = ["linux/amd64"]
}
