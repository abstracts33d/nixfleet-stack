{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  aiohttp,
}:
buildPythonPackage rec {
  pname = "hyxi-cloud-api";
  version = "1.1.5";
  pyproject = true;

  build-system = [ setuptools ];

  src = fetchPypi {
    pname = "hyxi_cloud_api";
    inherit version;
    hash = "sha256-73Fe3ypR++an3huvPGeYDwUvN4e37o5c55NNZNRExPk=";
  };

  dependencies = [ aiohttp ];

  # nixpkgs ships aiohttp 3.13.3; upstream requires >=3.13.5 (minor patch diff).
  pythonRelaxDeps = [ "aiohttp" ];

  doCheck = false; # network-bound

  meta = {
    description = "Async API client for HYXi Cloud";
    homepage = "https://pypi.org/project/hyxi-cloud-api/";
    license = lib.licenses.mit;
  };
}
