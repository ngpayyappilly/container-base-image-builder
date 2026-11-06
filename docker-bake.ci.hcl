// Layered on top of docker-bake.hcl for release builds only:
//   docker buildx bake -f docker-bake.hcl -f pins.hcl -f docker-bake.ci.hcl --push
// Bake merges same-named targets across files, so this extends _common for everything.
target "_common" {
  platforms = ["linux/amd64", "linux/arm64"]
  attest = [
    "type=sbom",
    "type=provenance,mode=max",
  ]
}
