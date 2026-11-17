# Single place to bump on a new upstream release:
# change the version, rename the URLs, and replace the hashes.
# Get the SRI hash of a new file with:
#   nix store prefetch-file --hash-type sha256 --json <url>
{
  version = "4.0.24";
  sources = {
    x86_64-linux = {
      url = "https://github.com/ymusic-io/YMusicV4/releases/download/release-v4.0.24/YMusic-4.0.24-linux-x86_64.AppImage";
      hash = "sha256-HUqgY2+LKXK5tcZ2NnZxdzcEtyTT83icBC7I0AZXj1o=";
    };
    aarch64-linux = {
      url = "https://github.com/ymusic-io/YMusicV4/releases/download/release-v4.0.24/YMusic-4.0.24-linux-arm64.AppImage";
      hash = "sha256-Ni7lKddvfvEbQd+D425s3OzuxbFiuTiIGJ42+8ZufHU=";
    };
  };
}
