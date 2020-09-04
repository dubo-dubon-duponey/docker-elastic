target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Elastic"
    BUILD_DESCRIPTION = "A dubo image for Elastic"
  }
  tags = [
    "dubodubonduponey/elastic",
  ]
  platforms = [
    "linux/amd64",
    "linux/arm64",
  ]
}
