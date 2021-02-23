package bake

command: {
  image: #Dubo & {
    args: {
      BUILD_TITLE: "Elastic"
      BUILD_DESCRIPTION: "A dubo image for Elastic based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }

    platforms: [
      AMD64,
      ARM64,
    ]
  }
}



