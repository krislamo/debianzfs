# DebianZFS

DebianZFS is a bash script that automates a UEFI Debian installation on an encrypted ZFS pool. The script installs `zfsutils-linux` on Debian Live, then proceeds to partition, create the boot and root zpools, and [debootstraps](https://wiki.debian.org/Debootstrap) a minimal system.

Due to [licensing concerns with OpenZFS and Linux](https://openzfs.github.io/openzfs-docs/License.html), distributing the resulting binaries together in a disk image may be a copyright violation. However, nothing keeps you from legally building and keeping your own disk images.

- Requires packer and qemu to build images


### Quick Start
1. Clone the repository and navigate into the directory
    ```
    git clone https://git.krislamo.org/kris/debianzfs
    cd debianzfs
    ```
2. Build image
    ```
    make
    ```
3. Copy qcow2 image to libvirt/images
    ```
    sudo cp output/debianzfs.qcow2 /var/lib/libvirt/images/
    ```
4. Grab auto-generated passwords from the log
    ```
    grep PW= debianzfs.log
    ```
5. Make a Libvirt VM and start
    ```
    sudo virt-install --name debianzfs \
      --description 'Debian ZFS' \
      --ram 2048 \
      --vcpus 2 \
      --disk /var/lib/libvirt/images/debianzfs.qcow2 \
      --os-type generic  \
      --network bridge=virbr0 \
      --graphics vnc,listen=127.0.0.1,port=5901 \
      --boot uefi,loader=/usr/shar/OVMF/OVMF_CODE.fd
    ```
6. If dropped into initramfs
    ```
    zpool import -f rpool
    exit
    ```
7. Enter rpool password
8. Login with root's password

### License
- DebianZFS is licensed under 0BSD, a public domain equivalent license; see the `LICENSE` file for more information