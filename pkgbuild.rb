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
                 orig_branch="plamo-8.x",
                 compare_branch="update-8.x",
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
      output_log("git fetch origin")
      system("git fetch origin")
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

  attr_reader :package_name
  attr_reader :package_category
  attr_reader :ct_category
  attr_accessor :mirror_srv
  attr_accessor :mirror_path
  attr_accessor :release
  attr_accessor :majorver
  attr_accessor :addon_pkgs
  attr_accessor :ct_loglevel

  def initialize(path, release, addon="")
    @package_path = path
    @mirror_srv = "repository.plamolinux.org"
    @mirror_path = "/pub/linux/Plamo"
    @release = release
    @majorver = @release[0].to_i
    if @majorver == 6 then
      @addon_pkgs = "plamo/05_ext/devel2.txz/git plamo/02_x11/expat #{addon}"
      @@category = ["02_x11", "03_xclassics", "04_xapps",
                    "05_ext", "06_xfce", "07_kde", "11_mate", "08_tex"]
    elsif @majorver >= 7 then
      # These addon pkgs needs from docbook2man
      @addon_pkgs = "#{addon} plamo/05_ext/perl_Parse_Yapp plamo/05_ext/perl_XML_NamespaceSupport plamo/03_libs/libxslt \
            plamo/05_ext/perl_SGMLSpm plamo/05_ext/perl_XML_SAX plamo/05_ext/perl_URI plamo/05_ext/perl_XML_SAX_Base plamo/05_ext/bind_tools plamo/03_libs/json_c plamo/03_libs/nss"
      @@category = ["03_libs", "04_x11", "05_ext", "06_xapps", "07_multimedia", "08_daemons",
                    "10_xfce", "11_lxqt", "12_mate", "13_tex" "16_virtualization"]
    end
    p @addon_pkgs
    @ignore_pkgs = "firefox thunderbird kernel "
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
    if @majorver == 6 then
      ct_category = "00_base 01_minimum 05_ext/docbook.txz "
      if @package_category == "00_base" ||
         @package_category == "01_minimum" ||
         @package_category == "02_devel" then
        @ct_category = ct_category
        return
      end
      @@category.each{|c|
        ct_category << "#{c} "
        if c == @package_category
          break
        end
      }
    elsif @majorver >= 7 then
      ct_category = "00_base 01_minimum 02_devel 09_printings "
      if @package_name.index("grub") then
        @addon_pkgs = "#{@addon_pkgs} plamo/04_x11/fonts.txz/dejavu_fonts_ttf plamo/05_ext/fuse2 plamo/03_libs/freetype"
        ct_category << "03_libs "
      elsif @package_name.index("vala") then
        @addon_pkgs = "#{@addon_pkgs} plamo/03_libs/glib"
      elsif @package_name.index("sqlite") then
        @addon_pkgs = "#{@addon_pkgs} plamo/06_xapps/tcl"
      elsif @package_name.index("gtk4") then
        @addon_pkgs = "#{@addon_pkgs} plamo/07_multimedia/gstreamer.txz/gst_plugins_bad plamo/07_multimedia/gstreamer.txz/gstreamer plamo/07_multimedia/gstreamer.txz/orc plamo/07_multimedia/gstreamer.txz/gst_plugins_base"
      elsif @package_name.index("source_highlight") then
        @addon_pkgs = "#{@addon_pkgs} plamo/03_libs/boost"
      end
      case @package_category
      when "03_libs" then
        ct_category << "03_libs "
      when "04_x11" then
        ct_category << "03_libs 04_x11 "
      when "05_ext" then
        ct_category << "03_libs 04_x11 05_ext "
      when "06_xapps" then
        ct_category << "03_libs 04_x11 05_ext 06_xapps "
      when "07_multimedia" then
        ct_category << "03_libs 04_x11 05_ext 06_xapps 07_multimedia "
      when "08_daemons" then
        ct_category << "03_libs 05_ext 08_daemons "
        @ignore_pkgs << "gpicview keybinder libfm libfm_extra lxappearance \
                lxappearance_obconf lxde_common lxde_icon_theme lxinput \
                lxmenu_data lxpanel lxrandr lxsession lxtask lxterminal \
                menu_cache pcmanfm"
      when "09_printings" then
        ct_category << "03_libs 04_x11"
      when "10_xfce" then
        ct_category << "03_libs 04_x11 05_ext 06_xapps 07_multimedia 10_xfce "
      when "11_lxqt" then
        ct_category << "03_libs 04_x11 05_ext 06_xapps 07_multimedia 11_lxqt "
      when "12_mate" then
        ct_category << "03_libs 04_x11 05_ext 06_xapps 07_multimedia 12_mate "
      when "13_tex" then
        ct_category << "03_libs 04_x11 "
      when "16_virtualization" then
        ct_category << "03_libs "
        @addon_pkgs = "#{@addon_pkgs} plamo/05_ext/fuse3"
      end
    end
    output_log("Installed packages to container are \"#{ct_category}\"")
    output_log("Addon packages are \"#{@addon_pkgs}\"")
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
    FileUtils.cp(path, path + ".orig")
    config = File.open(path, "a+")
    config.puts("lxc.mount.entry = #{ENV['HOME']}/.gnupg root/.gnupg none bind 0 0")
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
    if @majorver >= 7 then
      FileUtils.touch("/var/lib/lxc/pkgbuild_#{arch}/rootfs/etc/resolv.conf", :verbose => true)
    end
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

  def check_network(arch)
    command = %(lxc-attach -n pkgbuild_#{arch} -- /bin/bash -c "dig github.com")
    cnt = 0
    output_log("Check network is alive")
    while ! system(command) do
      sleep 5
      cnt = cnt + 1
      putc('.')
      if cnt > 20 then
        output_err("cannot resolv github.com")
        exit 1
      end
    end
    output_log("Network is OK")
    return true
  end

  def build_pkg(pkg, arch, branch)
    repo = PlamoSrc.new
    repo.compare_branch = branch
    if !ct_running?(arch) then
      output_log("container is not running. start container pkgbuild_#{arch}.")
      start_ct(arch)
    end

    # For debug
    common = %(lxc-attach -n pkgbuild_#{arch} -- /bin/bash -c )
    # common = %(lxc-attach -v GIT_CURL_VERBOSE=1 -n pkgbuild_#{arch} -- /bin/bash -c )


    # remove all libtool archive files in the container
    command = %(#{common} "/usr/bin/remove-la-files.sh")
    output_log("Remove all *.la files")
    if ! system(command) then
      output_err("failed to remove all *.la files")
    end

    # clone Plamo-src if not exists
    if !Dir.exist?("/var/lib/lxc/pkgbuild_#{arch}/rootfs/Plamo-src") then
      output_log("Waiting for starting container")
      check_network(arch)

      command = %(#{common} "git clone #{repo.remote_repo}")
      output_log("execute \"#{command}\"")
      if ! system(command) then
        output_err("git clone failed: #{$?}")
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
    levelstr = "B"
    if @majorver == 6 then
      levelstr = "P"
    end
    Dir.glob("/var/lib/lxc/pkgbuild_#{arch}/rootfs/Plamo-src/#{@package_path}/*-#{levelstr}*.t*").each {|fullpath|
      pkgfile = File.basename(fullpath)
      begin
        FileUtils.copy(fullpath, "./#{pkgfile}")
      rescue
        return false
      end
    }
    return true
  end

  def install_package(arch)
    levelstr = "B"
    if @majorver == 6 then
      levelstr = "P"
    end
    path_in_container = "/Plamo-src/#{@package_path}/*-#{levelstr}*.t*"
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

config[:compare_branch] = "update-8.x"
opts.on("-b", "--branch BRANCH",
        "branch that compare with original branch.") {|b|
  config[:compare_branch] = b
}
config[:orig_branch] = "plamo-8.x"
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
        "directory name of local git repository") {|r|
  config[:repo] = r
}
config[:keep_container] = false
opts.on("-k", "--keep",
        "keep the container") {|k|
  config[:keep_container] = true
}
config[:release] = "8.x"
opts.on("-R", "--release RELEASE",
        "Specify release version") {|release|
  config[:release] = release
}
config[:arch] = nil
opts.on("-a", "--arch=ARCH,ARCH,...", Array,
        "architecture(s) to create package") {|a|
  p a
  config[:arch] = a
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
config[:mirror_path] = "/pub/linux/Plamo"
opts.on("-m", "--mirror-path PATH",
        "directory path for downloading packages(ex. /pub/linux/Plamo)") {|mirror_path|
  config[:mirror_path] = mirror_path
}

opts.parse!(ARGV)

if config[:arch] == nil
  if config[:release] == "6.x"
    config[:arch] = ["x86", "x86_64"]
  else
    config[:arch] = ["x86_64"]
  end
end

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

  build = PkgBuild.new(pkg, config[:release], config[:appendpkg])
  build.ct_loglevel = config[:loglevel]
  build.mirror_path = config[:mirror_path]
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
