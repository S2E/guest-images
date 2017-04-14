Automated Guest Image Creation Tools
====================================

This repository contains a Makefile that allows building guest images suitable
for running in S2E. The creation process is fully automated.

# Installing dependencies

```
sudo apt-get install libguestfs-tools genisoimage python-pip xz-utils docker.io p7zip
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

# Building images

```
git clone https://github.com/s2e/guest-images
cd /home/user/s2e/guest-images

S2E_INSTALL_ROOT=/home/user/s2e/build/opt \
  S2E_LINUX_KERNELS_ROOT=/home/user/s2e-linux-kernel \
  make all -j3
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

Each build is composed of a json file that describes how to run the image, the image itself,
as well as a "ready" snapshot.

The build process also creates ```.stamps``` and ```.tmp-output```. The first contains
stamp files to keep track of which parts have been built, while the second contains
intermediate build output (e.g., kernel images and ISO files).

# Customization and debugging

If something goes wrong, you may want to turn on graphics output.
Open the makefile and comment out the ```GRAPHICS``` variable.

You may add additional packages to the base image by customizing the
```Linux/bootcd/preseed.cfg``` file.
