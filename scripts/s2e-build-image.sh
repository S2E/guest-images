#!/bin/bash

# Copyright (c) 2024 IBM Corporation
#
# Author: Andrea Mambretti <amb@zurich.ibm.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

DISTRO="jammy"
KERNEL="6.8-rc1"
ARCH="amd64"
REPO="http://de.archive.ubuntu.com/ubuntu"
CORES=`nproc --all`
SWAPFS_SIZE="4G"
QCOW_SIZE="30"
SKIP=""
NBD_DEV=/dev/nbd0
COMPILER=gcc

log() {
    printf '\033[0;32m->\033[m %s.\n' "$*"
}

warn() {
    printf '\033[0;33m->\033[m %s.\n' "$*"
}

err() {
    printf '\033[0;31m->\033[m %s.\n' "$*"
}

die() {
    err "$*" >&2
    exit 1
}

read_commandline() {
    log "Parsing commandline arguments"; {
        # Exit if we run out of parameters
        VALID_ARGS=$(getopt -o s:n:k:c:h --long name:,kernel:,cores:,size:,kernel-path:,skip-debootstrap,skip-kernel,skip-s2e-kprobe-module,compiler:,help -- "$@")

        [ $? -eq 0 ] || {
            echo "No parameters passed"
            exit 1
        }

        eval set -- "${VALID_ARGS}"

        while true; do
            case "${1}" in
            -s|--size)
                QCOW_SIZE=${2}
                ;;
            -c|--cores)
                CORES=${2}
                ;;
            -n|--name)
                DISTRO=${2}
                ;;
            -k|--kernel)
                KERNEL=${2}
                ;;
            --skip-debootstrap)
                SKIP="${SKIP}:run_debootstrap:install_s2e_packages:install_users2e_files"
                ;;
            --skip-kernel)
                SKIP="${SKIP}:fetch_kernel:compile_kernel:config_kernel:compile_kernel:install_kernel"
                ;;
            --skip-s2e-kprobe-module)
                SKIP="${SKIP}:init_build_s2e_module:sync_s2e_module"
                ;;
            --compiler)
                COMPILER=${2}
                ;;
            --kernel-path)
                KERNELPATH=${2}
                SKIP="${SKIP}:fetch_kernel:config_kernel:compile_kernel"
                ;;
            -h| --help)
                echo -e "\033[0;32m%%%%%%%%%%%%%  Alternative S2E build image program based on kprobe (experimental) %%%%%%%%%%%%%%\033[m"
                echo -e "\033[0;33mmake sure S2EDIR is set by sourcing s2e_activate!\033[m"
                echo -e "\033[0;33mrun default mode: sudo --preserve-env=S2EDIR bash s2e-build-image.sh\033[m\n"
                echo -e "Available configuration options:\n"
                echo -e "-s SIZE | --size SIZE:\t\t\tSpecify SIZE of QCOW image in GB\n"
                echo -e "-c N_CORES | --cores N_CORES:\t\tSpecify max number of cores used for compilation\n"
                echo -e "-n NAME | --name NAME:\t\t\tSpecify which version of debian/ubuntu to retrive through debootstrap (e.g., jammy, focal)\n"
                echo -e "-k KERNEL_TAG | --kernel KERNEL_TAG:\tSpecify the tag version to clone from github.com/torvalds/linux\n"
                echo -e "--compiler:\t\t\t\tOption to specify a different compiler to compile kernel and s2e module\n"
                echo -e "--kernel-path:\t\t\t\tOption to provide a different kernel source -- can be used to provide a custom (possibly instrumented) kernel\n"
                echo -e "-h | --help: \t\t\t\tOutput this message\n\n"
                echo -e "Available speedup options:\n"
                echo -e "--skip-debootstrap:\t\t\tOption to skip debootstrap rootfs initialization and configuration when the cached one is already available and ready\n"
                echo -e "--skip-kernel:\t\t\t\tOption to skip the cloning/compilation/installation of the kernel when the cached one is already available and ready\n"
                echo -e "--skip-s2e-kprobe-module:\t\tOption to skip the compilation/installation of the kprobe kernel module when the cached one is already available and ready\n"
                exit
                ;;
            --)
                shift
                break
                ;;
            esac
            shift
        done
    }
}

skip_step () {
    if [[ ${SKIP} == *$1* ]]; then
        false
    else
        true
    fi
}

run_debootstrap() {
    log "Running debootstrap arch=${ARCH} distr=${DISTRO} dir=${ROOTFS}"; {
        debootstrap --arch ${ARCH} ${DISTRO} ${ROOTFS} ${REPO} 1>/dev/null
    }
}

install_s2e_packages() {
    # preparing for chroot
    mount -t proc /proc ${ROOTFS}/proc
    mount -t sysfs /sys ${ROOTFS}/sys
    mount -o bind,ro /dev ${ROOTFS}/dev
    mount -o bind /dev/pts ${ROOTFS}/dev/pts

    sudo -i chroot ${ROOTFS} /bin/bash  <<END

    if ! test -f /etc/apt/sources.list.bak; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
    fi

    cat /etc/apt/sources.list.bak | head -n1 | cut -d " " -f2 | xargs -I {} printf "deb {} ${DISTRO} main \ndeb {} ${DISTRO}-updates main \ndeb {} ${DISTRO} universe\n " > /etc/apt/sources.list

    echo "/dev/sda1     none    swap    sw              0 0" > /etc/fstab
    echo "/dev/sda2     /       ext4    errors=remount-ro 0 1" >> /etc/fstab

    # adding s2e user with home directory
    groupadd s2e
    useradd -m s2e -s /bin/bash -g users -G tty,dialout,s2e

    # updating the password
    # usermod -p `printf 's2e' | openssl passwd -6 -salt 'FhcddHFVZ7ABA4Gi' -stdin` s2e
    echo 's2e:s2e' | chpasswd

    apt update && apt upgrade -y

    #echo  "allow-hotplug enp0s0" > /etc/network/interfaces.d/enp0s0
    #echo "iface enp0s0 inet dhcp" >> /etc/network/interfaces.d/enp0s0

    #echo "auto lo" >> /etc/network/interfaces
    #echo "iface lo inet loopback" >> /etc/network/interfaces

    echo "s2e" > /etc/hostname

    # installing basic utilities
    DEBIAN_FRONTEND=noninteractive apt install -y vim openssh-server build-essential python3-dev python3-setuptools gcc g++ libc-dbg gdb valgrind strace git libdw-dev elfutils gettext libelf1 tmux htop

    DEBIAN_FRONTEND=noninteractive apt --reinstall install -y grub-pc

    # removing sudo password requirement for s2e user
    echo 's2e ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/s2e

    # updating grub kernel parameters to get debug on serial console
    sed -ie 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200n8 earlyprintk=serial net.ifnames=0 nokaslr"/' /etc/default/grub
    sed -ie 's/quiet splash//' /etc/default/grub

    # change to serial console
    sed -ie 's/#GRUB_TERMINAL=.*/GRUB_TERMINAL="console serial"/' /etc/default/grub
    grep -qxF 'GRUB_SERIAL_COMMAND' /etc/default/grub || echo 'GRUB_SERIAL_COMMAND="serial --unit=0 --speed=9600 --stop=1"' >> /etc/default/grub


    # removing timeout
    sed -ie 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=4/' /etc/default/grub

    sed -ie 's/#GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub


    systemctl enable getty@tty1.service
    #systemctl enable getty@ttyS0.service
END

    umount ${ROOTFS}/dev/pts
    umount ${ROOTFS}/dev
    umount ${ROOTFS}/sys
    umount ${ROOTFS}/proc
}

install_grub() {
    mount -t proc /proc ${MNTDIR}/proc
    mount -t sysfs /sys ${MNTDIR}/sys
    mount -o bind,ro /dev ${MNTDIR}/dev
    mount -o bind /dev/pts ${MNTDIR}/dev/pts

    sudo -i chroot ${MNTDIR} /bin/bash  <<END
    # updating grub
    grub-install /dev/nbd0
    grub-mkconfig -o /boot/grub/grub.cfg
    sed -i 's/nbd0p2/sda2/g' /boot/grub/grub.cfg
END
    umount ${MNTDIR}/dev/pts
    umount ${MNTDIR}/dev
    umount ${MNTDIR}/sys
    umount ${MNTDIR}/proc

}

fetch_kernel() {
    log "Cloning v${KERNEL} in ${KERNELPATH}"; {
        git clone --depth 1 -b v${KERNEL} -- https://github.com/torvalds/linux.git ${KERNELPATH} 2> /dev/null || true
    }

    KERNELFULL=$(make --no-print-directory -C ${KERNELPATH} kernelversion)
}

compile_kernel() {
    log "Compiling kernel"; {
        #$KERNELPATH/scripts/config --disable SYSTEM_TRUSTED_KEYS
        #$KERNELPATH/scripts/config --disable SYSTEM_REVOCATION_KEYS
        make -C ${KERNELPATH} -j${CORES} 1>/dev/null
    }
}

install_kernel() {
    log "Installing kernel modules"; {
        make -C $KERNELPATH modules_install INSTALL_MOD_PATH=${ROOTFS} 1>/dev/null
    }
    log "Installing kernel headers"; {
        make -C $KERNELPATH headers_install INSTALL_HDR_PATH=${ROOTFS}/usr 1>/dev/null
    }
    log "Installing kernel image in ${ROOTFS}/boot"; {
        make -C $KERNELPATH install INSTALL_PATH=${ROOTFS}/boot 1>/dev/null
    }
}

config_kernel() {
    # checking the version of the kernel required to select the config file accordingly
    case ${KERNEL::1} in
        4)
            echo "4 detected";
            CONFNAME="4.0.config"
            ;;
        5)
            echo "5 detected";
            CONFNAME="5.0.config"
            ;;
        6)
            echo "6 detected";
            CONFNAME="6.0.config"
            ;;
    esac
    log "Installing config file for kernel"; {
        cp $KERNCONFDIR/$CONFNAME $KERNELPATH/.config
    }
    log "Adjusting config to current kernel home"; {
        make olddefconfig -C $KERNELPATH
    }
}

init_build_s2e_module() {
    # Copy s2e kprobe kernel in the working directory and compile againt the cloned kernel
    log "Installing s2e kernel module"; {
        rsync -az --partial $S2EKERNMODDIR $WORKDIR/ --exclude .git
    }
    log "Compiling s2e kernel module against current kernel"; {
        make -C $WORKDIR/s2e-kprobe CC=$COMPILER KERNELPATH=$KERNELPATH KERNELFULL=$KERNELFULL WORKDIR=$WORKDIR
    }
}

connect_image() {
    log "Inserting NBD kernel module"; {
        modprobe nbd
    }
    log "Connecting qemu image $QEMUIMG to $NBD_DEV"; {
        qemu-nbd -f raw -c $NBD_DEV $QEMUIMG || exit 1
    }
}

disconnect_image() {
    log "Disconnecting qemu image $QEMUIMG to $NBD_DEV"; {
        qemu-nbd --disconnect $NBD_DEV
    }
    log "Removing NBD kernel module"; {
        rmmod nbd
    }
}

load_uuid() {
    udevadm trigger
    root_uuid="$(blkid | grep '^`${NBD_DEV}`' | grep ' LABEL="root" ' | grep -o ' UUID="[^"]\+"' | sed -e 's/^ //' )"
}

mount_rootfs() {
    log "Mounting ${NBD_DEV}p2 at ${MNTDIR}"; {
        mount ${NBD_DEV}p2 ${MNTDIR}
    }
}

umount_rootfs() {
    log "Unmounting ${MNTDIR}"; {
        umount ${MNTDIR}
    }
}

format_image() {
    parted ${NBD_DEV} --script mklabel msdos
    parted ${NBD_DEV} -a optimal --script mkpart primary linux-swap 1M ${SWAPFS_SIZE}
    parted ${NBD_DEV} -a optimal --script mkpart primary ext4 ${SWAPFS_SIZE} 100%
    mkswap ${NBD_DEV}p1
    mkfs.ext4 -F ${NBD_DEV}p2
}

prepare_image() {
    log "Preparing the image"; {
    if ! test -f ${QEMUIMG}; then
        qemu-img create -f raw ${QEMUIMG}  ${QCOW_SIZE}G
        chown ${SUDO_USER}:${SUDO_USER} ${QEMUIMG}
    else
        warn "The image ${QEMUIMG} already exist"; {}
    fi
    }
}

sync_rootfs_image() {
    log "Installing rootfs in the qcow image"; {
        rsync -az --exclude "root/.cache" --partial ${ROOTFS}/ ${MNTDIR}
    }
}

sync_s2e_module() {
    log "Installing s2e kprobe kernel module"; {
        rsync -L -az --exclude ".git/" --partial ${WORKDIR}/s2e-kprobe ${ROOTFS}/root/
    }
}

install_users2e_files() {
    log "Installing override file for autologin"; {
        mkdir -p ${ROOTFS}/home/s2e/ 2> /dev/null || true
        mkdir -p ${ROOTFS}/etc/systemd/system/getty@tty1.service.d/ 2> /dev/null || true
        mkdir -p ${ROOTFS}/etc/systemd/system/getty@ttyS0.service.d/ 2> /dev/null || true
        cp ${OVERRIDE} ${ROOTFS}/etc/systemd/system/getty@tty1.service.d/
        cp ${OVERRIDE} ${ROOTFS}/etc/systemd/system/getty@ttyS0.service.d/
        rsync -az ${GUESTTOOLS}/ ${ROOTFS}/home/s2e/
        cp ${S2EHOME}/.bash_login ${ROOTFS}/home/s2e/
    }
}

init_workdir () {
    log "Initializing working directory at ${WORKDIR}"; {
        mkdir -p ${WORKDIR}  2> /dev/null || true
        chown ${SUDO_USER}:${SUDO_USER} ${WORKDIR}
    }
    log "Initializing kernel directory at ${KERNELPATH}"; {
        mkdir -p ${KERNELPATH} 2> /dev/null || true
        chown ${SUDO_USER}:${SUDO_USER} ${KERNELPATH}
    }
    log "Initializing output directory at ${OUTPUTDIR}"; {
        mkdir -p ${OUTPUTDIR} 2> /dev/null || true
    }
    log "Initializing mount directory ${MNTDIR}"; {
        mkdir -p ${MNTDIR} 2> /dev/null || true
    }
}

generate_final_s2e_image () {
    log "Creating s2e image ${QEMUIMGS2E} from ${QEMUIMG}"; {
        cp --reflink=auto ${QEMUIMG} ${QEMUIMGS2E}
        chown ${SUDO_USER}:${SUDO_USER} ${QEMUIMGS2E}
    }
}

create_snapshot () {
    log "Create snapshot"; {
        LD_PRELOAD=${S2EDIR}/install/share/libs2e/libs2e-x86_64.so ${S2EDIR}/install/bin/qemu-system-x86_64 -enable-kvm -drive if=ide,index=0,file=${QEMUIMGS2E},format=s2e,cache=writeback -serial file:${OUTPUTDIR}/serial_ready.txt -enable-serial-commands -net none -net nic,model=e1000 -m 1G -nographic
        chown ${SUDO_USER}:${SUDO_USER} ${QEMUIMGS2E}.ready
    }
}

create_manifest() {
    log "Create manifest"; {
        ${GUESTIMG}/scripts/generate_image_descriptor.py -i ${GUESTIMG}/images.json -o ${OUTPUTDIR}/image.json -n debootstrap snapshot="ready" qemu_build="x86_64" memory="1G" qemu_extra_flags="-net none -net nic,model=e1000"
    }
}

copy_guestfs() {
    log "Creating/Updating guestfs files in output"; {
        mkdir -p ${OUTPUTDIR}/guestfs 2> /dev/null || true
        rsync -az --partial ${ROOTFS}/ ${OUTPUTDIR}/guestfs/
    }
}

main() {
    # DEBUG mode
    #set -x

    [ "$(id -u)" = 0 ]  || die $0 needs to be run as root   
    command -v qemu-nbd >/dev/null || die  Qemu needs to be installed
    command -v wget >/dev/null || die Wget needs to be installed
    command -v rsync >/dev/null || die Rsync needs to be installed
    command -v sed >/dev/null || die Sed needs to be installed
    command -v find >/dev/null || die Find needs to be installed

    modprobe nbd || die NBD module is required

    # Check if we are in S2E Environment
    if [ -z ${S2EDIR+x} ]; then
        die "Not in a valid S2E Environment"
        die "run: source s2e_activate"
    fi

    read_commandline $@

    # Assuming this layout within S2E directory
    IMAGEDIR=${S2EDIR}/images # Default images directory
    GUESTIMG=${S2EDIR}/source/guest-images # Default guest-images directory
    S2ELINUX=${GUESTIMG}/Linux # Default Linux guest-images Linux directory
    KERNCONFDIR=${S2ELINUX}/configs # New kernel configs file for version 4.0/5.0/6.0
    S2EKERNMODDIR=${S2ELINUX}/s2e-kprobe # Folder for S2E kprobe kernel module
    OVERRIDE=${S2ELINUX}/override.conf # Default override file location to autologin
    S2EHOME=${S2ELINUX}/s2e_home # Default s2e home files
    WORKDIR=${IMAGEDIR}/.tmp-output/${DISTRO}-${KERNEL} # Default .tmp-output working directory for intermediate build files. Naming of the folder differ tho. 
    ROOTFS=${WORKDIR}/${DISTRO} # Debootstrap rootfs directory location
    MNTDIR=${WORKDIR}/chroot # Folder used to mount the guest image to final operations (e.g., bootloader installation)
    GUESTTOOLS=${S2EDIR}/install/bin/guest-tools64 # Default path to guest-tools
    OUTPUTDIR=${IMAGEDIR}/${DISTRO}-${KERNEL} # Final output location for the generated image and snapshot file
    QEMUIMG=${OUTPUTDIR}/image.raw # Default name for raw image
    QEMUIMGS2E=${OUTPUTDIR}/image.raw.s2e # Default name for s2e image

    if [ -z "${KERNELPATH}" ]; then
        KERNELPATH=${WORKDIR}/${KERNEL} # Location for cloned kernel within the working directory
    fi

    log Preparing debootstrap filesystem; {
         # Call to debootstrap to clone of the base rootfs
        if skip_step "run_debootstrap";  then
            run_debootstrap
        else
            warn "Skipping debootstrap initialization -- assuming debootstrap was already called"
        fi

        # Set basic files
        if skip_step "install_s2e_packages"; then
            install_s2e_packages
        else
            warn "Skipping installation s2e packages within debootstrap rootfs -- keeping cached values"
        fi

        # Install s2e files in the image
        if skip_step "install_users2e_files"; then
            install_users2e_files
        else
            warn "Skipping installation of s2e override files -- keeping cached values"
        fi

    }

    log Preparing kernel version; {
        # Initialize vaiours directories
        if skip_step "init_workdir"; then
            init_workdir
        else
            warn "Skipping initialization of working directories -- assuming already existing"
        fi

        # Clone the requested version of the kernel from git
        # unless another kernel base is provided (e.g., ad-hoc instrumented kernel)
        if skip_step "fetch_kernel"; then
            fetch_kernel
        else
            warn "Skipping kernel fetching from github"
            KERNELFULL=$(make --no-print-directory -C ${KERNELPATH} kernelversion)
        fi

        # Configure the kernel with the default configuration file
        if skip_step "config_kernel"; then
            config_kernel
        else
            warn "Skipping kernel configuration"
        fi

        # Compiler the kernel - make
        if skip_step "compile_kernel"; then
            compile_kernel
        else
            warn "Skipping kernel compilation"
        fi

        # Install the kernel - make install
        if skip_step "install_kernel"; then
            install_kernel
        else
            warn "Skipping kernel installation in the boot folder of rootfs"
        fi

        # Compile s2e kernel module against the selected kernel
        if skip_step "init_build_s2e_module"; then
            init_build_s2e_module
        else
            warn "Skipping s2e kprobe kernel module compilation"
        fi

        # Install s2e kernel module
        if skip_step "sync_s2e_module"; then
            sync_s2e_module
        else
            warn "Skipping s2e kprobe kernel module installation in rootfs"
        fi
    }

    log Preparing qcow qemu image; {
        # Create the image file
        if skip_step "prepare_image"; then
            prepare_image
        fi

        # Connect image through NBD driver
        if skip_step "connect_image"; then
            connect_image
        fi

        # Format image
        if skip_step "format_image"; then
            format_image
        fi

        # Mount rootfs at the mountpoint
        if skip_step "mount_rootfs"; then
            mount_rootfs
        fi

        # Install rootfs in the image
        if skip_step "sync_rootfs_image"; then
            sync_rootfs_image
        fi

        # Install grub
        if skip_step "intall_grub"; then
            install_grub
        fi

        if skip_step "umount_rootfs"; then
            umount_rootfs
        fi

        if skip_step "disconnect_image"; then
            disconnect_image
        fi
    }

    log Finalizing the image; {
        if skip_step "generate_final_s2e_image"; then
            generate_final_s2e_image
        fi

        if skip_step "create_snapshot"; then
            create_snapshot
        fi

        if skip_step "copy_guestfs"; then
            copy_guestfs
        fi

        if skip_step "create_manifest"; then
            create_manifest
        fi
    }
}

main "$*"
