Automated Guest Image Creation Tools
====================================

This repository contains a Makefile that allows building guest images suitable for running in S2E. The creation process
is fully automated.

# Installing dependencies

```
sudo apt-get install libguestfs-tools genisoimage python-pip python-magic xz-utils docker.io p7zip-full pxz libhivex-bin fuse
sudo apt-get build-dep fakeroot linux-image$(uname -r)
sudo pip install jinja2

# This is necessary for guestfish to work
sudo chmod +r /boot/vmlinuz*

# Re-login after running these commands
sudo usermod -a -G docker $(whoami)
sudo usermod -a -G kvm $(whoami)
```

# Building S2E

Build and install S2E into some folder (e.g., ```/home/user/s2e/build/opt/```).
Please refer to S2E build instructions for details.

# Checking out the kernel repository
```
cd /home/user
git clone https://github.com/s2e/s2e-linux-kernel
```

# Building Linux images

```
git clone https://github.com/s2e/guest-images
cd /home/user/s2e/guest-images

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

# Building Windows images

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


```
cd /home/user/s2e/guest-images

mkdir iso && cd iso
# Download Windows ISO images (e.g., from MSDN)
# See images.json for details.
wget ...
cd ..

S2E_INSTALL_ROOT=/home/user/s2e/build/opt \
  S2E_LINUX_KERNELS_ROOT=/home/user/s2e-linux-kernel \
  make windows -j3
```

The installation process takes periodic screenshots that are stored in ``.tmp-output`` and ``output`` folders. Run
``find . -name *.png`` in order to locate them. Screenshots are useful for debugging, especially if you are adding
custom images.

You may add additional applications to the Windows images by following these steps:
- Add a rule to ``Makefile.windows`` in order to download the installer package. The package must allow unattended
  installation (i.e., not have any dialog prompts, reboot after install must be disabled)
- If you can't find a suitable installer package, you may also zip the app into a file to be placed into
  ``Windows/install_scripts/inst``.
- Add an installation script to ``Windows/install_scripts``. This can be as simple as invoking the installer or
  unzipping the package into the right destination.


# Customization and debugging

If something goes wrong, you may want to turn on graphics output. Open the makefile and comment out the ```GRAPHICS```
variable.

You may add additional packages to the base image by customizing the ```Linux/bootcd/preseed.cfg``` file.
