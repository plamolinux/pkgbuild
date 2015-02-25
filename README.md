# pkgbuild

## Requirements

* Plamo Linux x86_64 host (if make a package of x86_64 arch)
* ruby
* git
* LXC

## Usage

At this time, this needs to run by root.

```
# ./pkgbuild.rb -h
Usage: pkgbuild [options]
    -b, --branch BRANCH              branch that compare with master branch.
        --basedir=DIR                directory under that repository is cloned.
    -r, --repository=DIR             directory name of local repository
    -k, --keep                       keep the container
    -a, --arch=ARCH,ARCH,...         architecture(s) to create package
    -f, --fstype FSTYPE              type of filesystem that the container will be created
    -i, --install                    install the created package into container
```
