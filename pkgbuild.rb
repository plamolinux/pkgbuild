#!/usr/bin/ruby

require 'fileutils'
require 'optparse'

# TODO: change to use Logger class
def output_log(log)
  puts "\e[32m#{log}\e[m\s"
end

def output_err(log)
  warn "\e[31m#{log}\e[m\s"
end

class PlamoSrc

  attr_accessor :remote_repo
  attr_accessor :compare_branch
  attr_accessor :update_pkgs

  def initialize(basedir=".",
                 orig_branch="plamo-7.x",
                 compare_branch="updatepkg",
                 repo="Plamo-src",
                 remote_repo="https://github.com/plamolinux/Plamo-src.git")

    @basedir = basedir
    @remote_repo = remote_repo
    @orig_branch = orig_branch
    @compare_branch = compare_branch
    @local_repo = "#{@basedir}/#{repo}"
  end

  def exist?
    Dir.exist?(@local_repo)
  end

  def clone
    output_log("git clone #{@remote_repo} && cd #{@local_repo} && git checkout -b #{@orig_branch} origin/#{@orig_branch}")
    system("git clone #{@remote_repo} && cd #{@local_repo} && git checkout -b #{@orig_branch} origin/#{@orig_branch}")
  end

  def update_local_repo
    Dir.chdir(@local_repo) {
      output_log("git checkout -b #{@orig_branch} origin/#{@orig_branch} || git checkout #{@orig_branch} && git pull origin #{@orig_branch}")
      system("git checkout -b #{@orig_branch} origin/#{@orig_branch} || git checkout #{@orig_branch} && git pull origin #{@orig_branch}")
    }
  end

  def fetch_compare_branch
    Dir.chdir(@local_repo) {
      output_log("git fetch origin #{@compare_branch}")
      system("git fetch origin #{@compare_branch}")
    }
  end

  def get_update_dirs
    Dir.chdir(@local_repo) {
      pkgs = `git diff --dirstat=0 #{@orig_branch} origin/#{@compare_branch} | awk '{ print $2 }'`
      output_log("update pkg list is '#{pkgs}'")
      @update_pkgs = pkgs.split("\n")
    }
  end

  def delete_contrib
    del_pkgs = Array.new
    @update_pkgs.each {|pkg|
      if (pkg.include?("contrib/") || pkg.include?("admin/")) then
        del_pkgs << pkg
      end
    }
    del_pkgs.each {|pkg|
      @update_pkgs.delete(pkg)
    }
  end

  # get updated pkgs except contrib
  def get_update_pkgs
    get_update_dirs
    delete_contrib
    return @update_pkgs
  end

end

class PkgBuild

  @@category = ["02_x11", "03_xclassics", "04_xapps",
                "05_ext", "06_xfce", "07_kde", "11_mate", "08_tex"]

  attr_reader :package_name
  attr_reader :package_category
  attr_reader :ct_category
  attr_accessor :mirror_srv
  attr_accessor :mirror_path
  attr_accessor :release
  attr_accessor :addon_pkgs
  attr_accessor :ct_loglevel

  def initialize(path, addon="")
    @package_path = path
    @mirror_srv = "repository.plamolinux.org"
    @mirror_path = "/pub/linux/Plamo"
    @release = "6.x"
    @addon_pkgs = "plamo/05_ext/devel2.txz/git plamo/02_x11/expat #{addon}"
    p @addon_pkgs
    @ignore_pkgs = "firefox thunderbird kernel kmod"
  end

  def get_lxc_version
    return IO.popen("lxc-ls --version").getc.to_i
  end

  def get_package_info
    dir_array = @package_path.split("/")
    @package_name = dir_array[dir_array.length - 1]
    @package_category = dir_array[1]
  end

  def define_ct_category
    ct_category = "00_base 01_minimum 05_ext/docbook.txz "
    if @package_category == "00_base" ||
       @package_category == "01_minimum" then
      @ct_category = ct_category
      return
    end
    @@category.each{|c|
      ct_category << "#{c} "
      if c == @package_category
        break
      end
    }
    output_log("Installed package to container is \"#{ct_category}\"")
    @ct_category = ct_category
  end

  def define_create_ct_env
    env = ""
    env << %!CATEGORIES="#{@ct_category}" !
    env << %!MIRRORSRV="#{@mirror_srv}" !
    env << %!MIRRORPATH="#{@mirror_path}" !
    env << %!ADDONPKGS="#{@addon_pkgs}" !
    env << %!IGNOREPKGS="#{@ignore_pkgs}" !
  end

  def customize_ct_config(arch)
    path = "/var/lib/lxc/pkgbuild_#{arch}/config"
    File.rename(path, path + ".orig")
    config = File.open(path, "a+")
    File.open(path + ".orig") {|io|
      while line = io.gets
        line.sub!(%r(^lxc.network.), "#lxc.network.")
        line.sub!(%r(^lxc.net.), "#lxc.net.")
        config.puts(line)
      end
      if get_lxc_version >= 3
        config.puts("lxc.net.0.type = none")
      else
        config.puts("lxc.network.type = none")
      end
      config.puts("lxc.mount.entry = #{ENV['HOME']}/.gnupg root/.gnupg none bind 0 0")
      config.puts("lxc.mount.entry = /etc/resolv.conf etc/resolv.conf none bind 0 0")
    }
    config.close
  end

  def create_ct(arch, opt={})
    get_package_info
    define_ct_category
    env = define_create_ct_env
    if opt.length > 0
      option = " "
      opt.each{|key,val|
        option << key << " " << val
      }
    end
    command = "#{env} lxc-create -n pkgbuild_#{arch} #{option} -t plamo -l #{@ct_loglevel} -- -a #{arch} -r #{@release} -c"
    system(command)
    customize_ct_config(arch)
    Dir.mkdir("/var/lib/lxc/pkgbuild_#{arch}/rootfs/root/.gnupg")
    File.unlink("/var/lib/lxc/pkgbuild_#{arch}/rootfs/etc/rc.d/rc.inet1")
    File.unlink("/var/lib/lxc/pkgbuild_#{arch}/rootfs/etc/rc.d/rc.inet1.tradnet")
  end

  def ct_exist?(arch)
    command = "lxc-info -n pkgbuild_#{arch} > /dev/null 2>&1"
    output_log("execute #{command}")
    system(command)
  end

  def start_ct(arch)
    command = "lxc-start -n pkgbuild_#{arch} -d -l #{@ct_loglevel}"
    output_log("execute \"#{command}\"")
    system(command)
  end

  def ct_running?(arch)
    command = "lxc-info -s -n pkgbuild_#{arch} | grep RUNNING"
    system(command)
  end

  def destroy_ct(arch)
    command = "lxc-stop -n pkgbuild_#{arch} -l #{@ct_loglevel}"
    if ! system(command) then
      output_err("Failed to stop container pkgbuild_#{arch}")
      exit 1
    end
    output_log("container pkgbuild_#{arch} has been stopped.")
    command = "lxc-destroy -n pkgbuild_#{arch} -l #{@ct_loglevel}"
    if system(command) then
      output_log("container pkgbuild_#{arch} has been destroyed.")
    else
      output_err("Failed to destroy container pkgbuild_#{arch}")
      exit 1
    end
  end

  def build_pkg(pkg, arch, branch)
    repo = PlamoSrc.new
    repo.compare_branch = branch
    if !ct_running?(arch) then
      output_log("container is not running. start container pkgbuild_#{arch}.")
      start_ct(arch)
    end
    common = %(lxc-attach -n pkgbuild_#{arch} -- /bin/bash -c )

    # clone Plamo-src if not exists
    if !Dir.exist?("/var/lib/lxc/pkgbuild_#{arch}/rootfs/Plamo-src") then
      command = %(#{common} "git clone #{repo.remote_repo}")
      output_log("execute \"#{command}\"")
      if ! system(command) then
        output_err("git clone failed")
        exit 1
      end

    # sync #{@orig_branch} branch to be up to date
    else
      command = %!#{common} "( cd /Plamo-src && \
        git checkout #{@orig_branch} && \
        git pull origin #{@orig_branch} )"!
    end

    # fetch branch to update package
    command = %!#{common} "( cd /Plamo-src && \
        git fetch origin #{repo.compare_branch} && \
        git checkout #{repo.compare_branch} && \
        git pull origin #{repo.compare_branch} )"!
    if ! system(command) then
      output_err("git fetch or checkout failed")
      exit 1
    end

    command = %!#{common} "( stat /Plamo-src/#{pkg} )"!
    if ! system(command) then
      output_err("#{pkg} is not exists.")
      return 1
    end

    command = %!#{common} "( ls /Plamo-src/#{pkg}/PlamoBuild.* )"!
    if ! system(command) then
      return 1
    end

    command = %!#{common} "( cd /Plamo-src/#{pkg} && ./PlamoBuild.* download )"!
    if ! system(command) then
      output_err("PlamoBuild download failed")
      exit 1
    end

    command = %!#{common} "( cd /Plamo-src/#{pkg} && ./PlamoBuild.* config )"!
    if ! system(command) then
      output_err("PlamoBuild config failed")
      exit 1
    end

    command = %!#{common} "( cd /Plamo-src/#{pkg} && ./PlamoBuild.* build )"!
    if ! system(command) then
      output_err("PlamoBuild config failed")
      exit 1
    end

    command = %!#{common} "( cd /Plamo-src/#{pkg} && ./PlamoBuild.* package )"!
    if ! system(command) then
      output_err("PlamoBuild config failed")
      exit 1
    end
  end

  def save_package(arch)
    fullpath = Dir.glob("/var/lib/lxc/pkgbuild_#{arch}/rootfs/Plamo-src/#{@package_path}/*-P*.txz").at(0)
    p fullpath
    pkgfile = File.basename(fullpath)
    begin
      FileUtils.copy(fullpath, "./#{pkgfile}")
    rescue
      return false
    end
    return true
  end

  def install_package(arch)
    path_in_container = "/Plamo-src/#{@package_path}/*-P*.txz"
    command = %(lxc-attach -n pkgbuild_#{arch} -- /bin/bash -c "updatepkg -f #{path_in_container}")
    output_log("exec command: #{command}")
    if ! system(command) then
      output_err("#{command} failed")
      exit 1
    end
  end

end

opts = OptionParser.new
config = Hash.new

config[:compare_branch] = "updatepkg"
opts.on("-b", "--branch BRANCH",
        "branch that compare with original branch.") {|b|
  config[:compare_branch] = b
}
config[:orig_branch] = "plamo-7.x"
opts.on("-o", "--orig ORIG_BRANCH",
        "original branch") {|o|
  config[:orig_branch] = o
}
config[:basedir] = "."
opts.on("--basedir=DIR",
        "directory under that repository is cloned.") {|d|
  config[:basedir] = d
}
config[:repo] = "Plamo-src"
opts.on("-r", "--repository=DIR",
        "directory name of local repository") {|r|
  config[:repo] = r
}
config[:keep_container] = false
opts.on("-k", "--keep",
        "keep the container") {|k|
  config[:keep_container] = true
}
config[:arch] = ["x86", "x86_64"]
opts.on("-a", "--arch=ARCH,ARCH,...", Array,
        "architecture(s) to create package") {|a|
  config[:arch] = a
}
config[:release] = "6.x"
opts.on("-R", "--release RELEASE",
        "Specify release version") {|release|
  config[:release] = release
}
config[:fstype] = "dir"
opts.on("-f", "--fstype FSTYPE",
        "type of filesystem that the container will be created") {|f|
  config[:fstype] = f
}
config[:install] = false
opts.on("-i", "--install",
        "install the created package into container") {|i|
  config[:install] = true
}
config[:appendpkg] = ""
opts.on("-A", "--append-pkgs APPEND",
        "additional packages to be installed") {|append|
  config[:appendpkg] = append
}
config[:loglevel] = "INFO"
opts.on("-l", "--logpriority LEVEL",
        "loglevel given to the container") {|loglevel|
  config[:loglevel] = loglevel
}

opts.parse!(ARGV)

repo = PlamoSrc.new(config[:basedir],
                    config[:orig_branch],
                    config[:compare_branch],
                    config[:repo])
if ! repo.exist? then
  output_log("Clone remote repository")
  if repo.clone then
    output_log("clone done")
  else
    output_err("clone error")
  end
else
  output_log("Update local repository")
  repo.update_local_repo
end

repo.fetch_compare_branch

repo.get_update_pkgs.each{|pkg|

  build = PkgBuild.new(pkg, config[:appendpkg])
  build.release = config[:release]
  build.ct_loglevel = config[:loglevel]
  config[:arch].each{|a|
    if !build.ct_exist?(a) then
      output_log("create container for building #{pkg}")
      build.create_ct(a, {"-B" => config[:fstype]})
    end
    if build.build_pkg(pkg, a, config[:compare_branch])
      next
    end
    if ! build.save_package(a)
      output_err("copy package failed")
    end
    if config[:install] then
      build.install_package(a)
    end
    if !config[:keep_container] then
      build.destroy_ct(a)
    end
  }
}
