# hyxi-cloud-api — async API client for HYXi Cloud (Home Assistant integration dependency).
# Source: https://pypi.org/project/hyxi-cloud-api/
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

  # aiohttp 3.13.3 in nixpkgs vs >=3.13.5 required — minor patch difference, works fine
  pythonRelaxDeps = [ "aiohttp" ];

  # Tests require network access
  doCheck = false;

  meta = {
    description = "Async API client for HYXi Cloud";
    homepage = "https://pypi.org/project/hyxi-cloud-api/";
    license = lib.licenses.mit;
  };
}
