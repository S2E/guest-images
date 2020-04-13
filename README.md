Automated Guest Image Creation Tools
====================================

This repository contains a Makefile that allows building guest images suitable for running in S2E. The creation process
is fully automated.

It is recommended to use the ``s2e image_build`` command in order to build images instead of calling the makefiles
directly. That command ensures that the makefile is called with the right arguments and that all requirements
are met. Please refer to the S2E documentation on how to use ``s2e image_build``. This README provides a reference
in case you want to modify the image build system or add new software to existing images.

# Installation

**It is recommended to use a file system that supports copy-on-write (XFS, ZFS, or BtrFS).** The image build system
copies images for intermediate build steps and copy-on-write will save you a lot of disk space.

## Installing dependencies

```
sudo apt-get install libguestfs-tools genisoimage python-pip python-magic xz-utils docker.io p7zip-full pxz libhivex-bin fuse jigdo-file
sudo apt-get build-dep fakeroot linux-image$(uname -r)
sudo pip install jinja2

# This is necessary for guestfish to work
sudo chmod +r /boot/vmlinuz*

# Re-login after running these commands
sudo usermod -a -G docker $(whoami)
sudo usermod -a -G kvm $(whoami)
```

## Building S2E

Build and install S2E into some folder (e.g., ```/home/user/s2e/build/opt/```).
Please refer to S2E build instructions for details.

## Checking out the kernel repository
```
cd /home/user
git clone https://github.com/s2e/s2e-linux-kernel
```

## Checking out guest-images repository

```
cd /home/user
git clone https://github.com/s2e/guest-images
```

# Building images

## Linux

```
cd /home/user/guest-images

S2E_INSTALL_ROOT=/home/user/s2e/build/opt \
  S2E_LINUX_KERNELS_ROOT=/home/user/s2e-linux-kernel \
  make linux -j3
```

The build should take around 30 minutes. The images will be placed in the ```output``` directory, which looks like this:

```
./debian-8.7.1-i386/image.json
./debian-8.7.1-i386/image.raw.s2e
./debian-8.7.1-i386/image.raw.s2e.ready

./debian-8.7.1-x86_64/image.json
./debian-8.7.1-x86_64/image.raw.s2e
./debian-8.7.1-x86_64/image.raw.s2e.ready

./cgc_debian-8.7.1-i386/image.json
./cgc_debian-8.7.1-i386/image.raw.s2e
./cgc_debian-8.7.1-i386/image.raw.s2e.ready
```

Each build is composed of a json file that describes how to run the image, the image itself, as well as a "ready"
snapshot.

The build process also creates ```.stamps``` and ```.tmp-output```. The first contains stamp files to keep track of
which parts have been built, while the second contains intermediate build output (e.g., kernel images and ISO files).

## Windows

First, you need to get the ISO file for the Windows version that you want to install. You can download these images from
MSDN. The hash and the name of the ISO is specified in the  ``images.json`` file. You can use the hash to make sure that
you downloaded the right version. Place the downloaded file in the ``iso`` folder.

Do not forget to update the ``product_key`` value in the ``images.json`` file. Some versions of Windows require one
for installation (e.g., XP). Other versions install without one. You should not need to activate Windows once a snapshot
is taken (time is frozen and the guest has no Internet access). Make sure you have the required licenses to install
and use Windows this way.

The ``images.json`` file lists all Windows versions that S2E officially supports. Other images may work too but we have
not tested them. If you want to add support for new images, you may need to also update ``s2e.sys`` in the
``guest-tools`` repository in order to support the different kernels. This may not be needed if the Windows version you
need uses the exact same kernel as an already supported one. Please refer to the documentation in ``guest-tools``.

Build scripts for Windows XP and Windows 7 install service packs and updates up to January 2016 and 2020 respectively.

```
cd /home/user/guest-images

mkdir iso && cd iso
# Download Windows ISO images (e.g., from MSDN)
# See images.json for details.
wget ...
cd ..

S2E_INSTALL_ROOT=/home/user/s2e/build/opt \
  S2E_LINUX_KERNELS_ROOT=/home/user/s2e-linux-kernel \
  make windows -j3
```

# Customizing images

## Linux

You can add additional packages to the base image by customizing the ```Linux/bootcd/preseed.cfg``` file.
Alternatively, you can modify ``Linux/s2e_home/launch.sh``. The VM has Internet access, so you can get any
additional packages you need from that script.

## Windows

Image building is divided into steps. Each step installs one or more software packages, then reboots the VM.
The last step boots the VM in TCG mode and takes a snapshot.

Each step mounts two CD drives:

1. The drive ``D:\`` contains all software packages to be installed (``00_software.iso``).
2. The drive ``E:\`` contains the scripts to install desired packages (e.g., ``05_dotnet.iso``).
   This drive is built from the folders in ``Windows/install_scripts``.

You may add additional applications to the Windows images by following these steps:

1. Add a rule to ``Makefile.windows.apps`` in order to download the installer package. The package must allow unattended
   installation (i.e., not have any dialog prompts, reboot after install must be disabled). The package will be
   automatically added to the ``00_software.iso`` disk.

2. Instead of downloading new software, you can place it in one of the installation folders
   (e.g., ``07_install_software``). If your software doesn't come with an installer, you can zip its files in an
   archive instead.

3. Modify the right ``launch.bat`` file to start the installer. In most cases, it will be
   ``07_install_software/launch.bat``. If you use a zip archive, call ``7z`` to decompress it.
   Refer to existing scripts for examples of how to do it.

The makefile detects modifications and additions to the folders in ``install_scripts``, and will automatically
start the installation from the updated step in order to minimize image build time.

Unlike Linux images, Windows VMs do not have Internet access. You must provide all additional software through
ISO images as explained above.

Note that by default, the makefile does not create intermediate copies of the guest image for each installation step
in order to save disk space. In practice, if you modify, e.g, the step ``07_install_software``, the guest image that
will be used to re-run this step will already contain changes done by subsequent steps. Read the next section to learn
how to modify this behavior.

The current image build system does not natively support software that comes on an ISO image (e.g., Microsoft Office).
You must modify the makefile to accommodate that (e.g., add an additional virtual drive with the desired software).

# Debugging

If something goes wrong, proceed as follows:

* If something gets stuck or crashes, look at screenshots. They may contain error messages or display blocking message
  boxes. The installation process takes screenshots every few seconds and stores them in the ``.tmp-output``
  directory of each image. Run ``find . -name *.png`` to find them.

* Turn on graphics output. Open the makefile and comment out the ```GRAPHICS``` variable.
  If you use ``s2e image_build``, add the ``-g`` option. This is convenient if you modify existing build scripts
  and want to monitor the installation as it goes.

* Look at the serial output. Most installation steps redirect stdout / stderr to the serial port, which is recorded
  in ``*_serial.txt`` files.

* Check that Virtual Box, VMware, or any other virtualization software is not running. It interferes with KVM.
  This should not be a problem if you use ``s2e image_build``, which checks this before starting the build process.

* If you need to debug an intermediate installation step on Windows, set ```DEBUG_INTERMEDIATE_RULES``` to 1.
  The makefile will checkpoint the disk images after each build step. If you abort the build, it will restart
  the aborted step using a fresh image copy from the previous build step.
