require 'formula'

DINGHY_VERSION='3.1.1'

class Dinghy < Formula
  homepage 'https://github.com/codekitchen/dinghy'
  url  'https://github.com/codekitchen/dinghy.git', tag: "v#{DINGHY_VERSION}"
  head 'https://github.com/codekitchen/dinghy.git', branch: :machine
  version DINGHY_VERSION

  depends_on 'docker'
  depends_on 'docker-machine'
  depends_on 'unfs3'

  def install
    bin.install "bin/dinghy"
    prefix.install "cli"
  end

  def caveats; <<-EOS.undent
    Run `dinghy up` to bring up the VM and services.
    EOS
  end
end
