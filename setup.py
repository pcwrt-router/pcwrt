#!/usr/bin/env python3
from pathlib import Path
from subprocess import run
import os
import sys
import yaml
import getopt

def clone_tree():
    try:
        makefile = openwrt +"/Makefile"
        if Path(makefile).is_file():
            print("### OpenWrt checkout is already present. Please run --rebase")
            sys.exit(-1)

        print("### Cloning tree")
        Path(openwrt).mkdir(exist_ok=True, parents=True)
        if git_ref != "":
            run(["git", "clone", "--reference", git_ref, config["repo"], openwrt], check=True)
        else:
            run(["git", "clone", config["repo"], openwrt], check=True)
        print("### Clone done")
    except:
        print("### Cloning the tree failed")
        sys.exit(1)

def fetch_tree():
    try:
        makefile = openwrt +"/Makefile"
        if not Path(makefile).is_file():
            print("### OpenWrt checkout is not present. Please run --setup")
            sys.exit(-1)

        print("### Fetch tree")
        os.chdir(openwrt)
        run(["git", "fetch"], check=True)
        print("### Fetch done")
    except:
        print("### Fetching the tree failed")
        sys.exit(1)
    finally:
        os.chdir(base_dir)

def reset_tree():
    try:
        print("### Resetting tree")
        os.chdir(openwrt)
        run(
            ["git", "checkout", config["branch"]], check=True,
        )
        run(
            ["git", "reset", "--hard", config.get("revision", config["branch"])],
            check=True,
        )
        print("### Reset done")
    except:
        print("### Resetting tree failed")
        sys.exit(1)
    finally:
        os.chdir(base_dir)

def _apply_patches():
    try:
        print("### Applying patches")
        patches = []
        patch_folders = config.get("patch_folders")
        if not patch_folders:
            patch_folders = []

        for folder in patch_folders:
            patch_folder = base_dir/folder
            if not patch_folder.is_dir():
                print(f"Patch folder {patch_folder} not found, ignoring...")
            else:
                print(f"Adding patches from {patch_folder}")
                patches.extend(
                    sorted(list((base_dir/folder).glob("*.patch")), key=os.path.basename)
                )

        print(f"Found {len(patches)} patches")

        os.chdir(openwrt)
        for patch in patches:
            run(["git", "am", "-3", str(patch)], check=True)
        print("### Patches done")
    except Exception as err:
        print(err)
        print("### Setting up the tree failed")
        sys.exit(1)
    finally:
        os.chdir(base_dir)

def _update_feeds():
    try:
        print('### Installing feeds')
        os.chdir(openwrt)
        run(
            ["scripts/feeds", "update", "-a"], check=True,
        )
        run(
            ["rm", "-rf", "feeds/luci/modules/luci-mod-pcwrt"], check=True,
        )
        run(
            ["cp", "-r", "../luci-mod-pcwrt", "feeds/luci/modules/"], check=True,
        )
        run(
            ["scripts/feeds", "update", "luci"], check=True,
        )
        run(
            ["sed", "-i", "s/cgi-bin\/luci/cgi-bin\/pcwrt/",
            "feeds/luci/modules/luci-base/root/www/index.html"], check=True,
        )
        run(
            ["scripts/feeds", "install", "-a"], check=True,
        )
        print("### Install feeds done")
    except Exception as err:
        print(err)
        print("### Setting up the tree failed")
        sys.exit(1)
    finally:
        os.chdir(base_dir)

def _reset_feeds_packages():
    try:
        print('### Resetting feeds/packages')
        os.chdir('%s/feeds/packages' % openwrt)
        run(["git", "reset", "--hard", config.get("feeds_packages_revision")], check=True)
    except:
        print('### Resetting feeds/packages failed')
    finally:
        os.chdir(base_dir)

def _apply_feeds_packages_patches():
    try:
        print('### Patching feeds/packages')
        patches = []
        patch_folders = config.get('feeds_packages_patch_folders')
        if not patch_folders:
            patch_folders = []

        for folder in patch_folders:
            patch_folder = base_dir/folder
            if not patch_folder.is_dir():
                print(f"Patch folder {patch_folder} not found, ignoring...")
            else:
                print(f"Adding patches from {patch_folder}")
                patches.extend(
                    sorted(list((base_dir/folder).glob("*.patch")), key=os.path.basename)
                )

        print(f"Found {len(patches)} patches")

        os.chdir('%s/feeds/packages' % openwrt)
        for patch in patches:
            run(["git", "am", "-3", str(patch)], check=True)
        print('### Done patching feeds/packages')
    except:
        print('### Patching feeds/packages failed')
    finally:
        os.chdir(base_dir)

def setup_tree():
    _apply_patches()
    _update_feeds()
    _reset_feeds_packages()
    _apply_feeds_packages_patches()

def update_patches():
    try:
        print("### Updating patches")
        run(
            ["rm", "-r", "patches"], check=True,
        )
        os.chdir(openwrt)
        run(
            ["git", "format-patch", config.get("revision", config["branch"]), "-o", "../patches"],
            check=True,
        )
        print("### Updating done")
    except:
        print("### updating failed failed")
        sys.exit(1)
    finally:
        os.chdir(base_dir)

base_dir = Path.cwd().absolute()
setup = False
update = False
rebase = False
config = "config.yml"
openwrt = "openwrt"
git_ref = ""

try:
    opts, args = getopt.getopt(sys.argv[1:], "srdc:f:u2", ["setup", "rebase", "config=", "folder=", "reference=", "update", "20x" ])
except getopt.GetoptError as err:
    print(err)
    sys.exit(2)

for o, a in opts:
    if o in ("-s", "--setup"):
        setup = True
    elif o in ("-r", "--rebase"):
        rebase = True
    elif o in ("-u", "--update"):
        update = True
    elif o in ("-c", "--config"):
        config = a
    elif o in ("--reference"):
        git_ref = a
    else:
        assert False, "unhandled option"

if not Path(config).is_file():
    print(f"Missing {config}")
    sys.exit(1)
config = yaml.safe_load(open(config))

if setup:
    clone_tree()
    reset_tree()
    setup_tree()
elif rebase:
    fetch_tree()
    reset_tree()
    setup_tree()
elif update:
    update_patches()
else:
    print("%s [-s|-r]" % sys.argv[0])
