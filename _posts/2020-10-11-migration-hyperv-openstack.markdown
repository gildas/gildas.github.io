---
layout: post
title:  "Migrating Hyper-V to OpenStack"
author: Gildas Cherruel
date:   2020-10-11 15:30:00 +0900
tags: hyperv openstack kvm libvirt migration
---
The other day I had to migrate Hyper-V Windows virtual machines to our [OpenStack][openstack] kvm/libvirt-based environment.

While I was able to find some information on the web, I could not find a definitive step-by-step guide.

The main difficulty with Windows Virtual Machine is their lack of [virtio][virtio] drivers, unlike Linux Virtual Machines. These drivers are essential if you want your Virtual Machines to be fast with libvirt.

## Preparation

You will need a host running [libvirt][libvirt]. Nowadays, libvirt runs on Linux primarily, but it can also run on [MacOS][qemu-macos] and [Windows][qemu-windows], although things get usually more complicated.

On Ubuntu, installing libvirt can be done like this (don't forget `ovmf` for UEFI-based virtual machines):
{% highlight sh %}
sudo apt install \
  qemu-kvm libvirt-clients libvirt-daemon-system ovmf \
  bridge-utils virt-manager
{% endhighlight %}

On RedHat/CentOS 8, that would be done like this:
{% highlight sh %}
sudo yum install \
  qemu-kvm libvirt libvirt-client libguestfs-tools \
  virt-install virt-viewer bridge-utils edk2-ovmf
{% endhighlight %}

In order to load virtual machines to OpenStack you will also need the [OpenStack Client][openstack-client] for your platform. Oh, and, of course an Openstack cluster...

On Ubuntu:
{% highlight sh %}
sudo apt install python3-openstackclient
{% endhighlight %}

On RedHat/CentOS 8:
{% highlight sh %}
sudo yum install python3-openstackclient openstack-selinux
{% endhighlight %}

Finally, download the virtio drivers:
{% highlight sh %}
curl -LO https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
{% endhighlight %}

## Convert the virtual disks

We will need to convert the Hyper-V virtual disks into the native format used by libvirt: `qcow2`.

Extrack the virtual disk (`vdhx`) from the Hyper-V server and copy it on your local machine, run a quick test and convert it:
{% highlight sh %}
qemu-img check -r all system-disk.vhdx
qemu-img convert -O qcow2 system-disk.vhdx system-disk.qcow2
{% endhighlight %}

Once this is done, we need to inject the virtio drivers in the virtual disk. The trick will be to attach another dummy virtual disk to the Windows Virtual Machine so the system can install the driver.

First, create a dummy disk:
{% highlight sh %}
qemu-img create -f qcow2 dummy.qcow2 1G
{% endhighlight %}

Then, run a virtual machine with IDE and virtio buses, along with the driver ISO:
{% highlight sh %}
virt-install --connect qemu:///system \
  --ram 2048 \
  --vcpus 2 --cpu host \
  --network network=default,model=virtio \
  --disk path=windows-disk.qcow2,device=disk,format=qcow2,bus=ide \
  --disk path=dummy.qcow2,format=qcow2,device=disk,bus=virtio \
  --disk path=./iso/virtio-win.iso,device=cdrom,perms=ro \
  --graphics vnc,listen=0.0.0.0,password=1234 --noautoconsole \
  --os-type windows --os-variant win2k12 \
  --import \
  --name myvm
{% endhighlight %}

**Note:** If the virtual disk runs with UEFI, add `--boot uefi`:
{% highlight sh %}
virt-install --connect qemu:///system \
  --ram 2048 \
  --vcpus 2 --cpu host \
  --network network=default,model=virtio \
  --disk path=windows-disk.qcow2,device=disk,format=qcow2,bus=ide \
  --disk path=dummy.qcow2,format=qcow2,device=disk,bus=virtio \
  --disk path=./iso/virtio-win.iso,device=cdrom,perms=ro \
  --graphics vnc,listen=0.0.0.0,password=1234 --noautoconsole \
  --boot uefi \
  --os-type windows --os-variant win2k12 \
  --import \
  --name myvm
{% endhighlight %}

Once the virtual machine has booted, log in (with virt-viewer, for instance) and install the drivers via PowerShell (this runs inside the virtual machine!):
{% highlight posh %}
cd d:\balloon\2k12R2\amd64
pnputil -i -a *.inf
cd \NetKVM\2k12R2\amd64
pnputil -i -a *.inf
cd \viostor\2k12R2\amd64
pnputil -i -a *.inf
Stop-Computer
{% endhighlight %}

When the virtual machine is shutdow, remove it from libvirt:
{% highlight sh %}
virsh undefine --nvram myvm
{% endhighlight %}

Finally, test the virtual machine to make sure the drivers work as intended:
{% highlight sh %}
virt-install --connect qemu:///system \
  --ram 2048 \
  --vcpus 2 --cpu host \
  --network network=default,model=virtio \
  --disk path=windows-disk.qcow2,device=disk,format=qcow2,bus=virtio \
  --graphics vnc,listen=0.0.0.0,password=1234 --noautoconsole \
  --os-type windows --os-variant win2k12 \
  --import \
  --name myvm
{% endhighlight %}

**Note:** Again, if the virtual disk runs with UEFI, add `--boot uefi`.

## Import the Virtual Machine in OpenStack

Now that we have a virtual disk that runs Windows with the virtio drivers, we can import it in OpenStack.

First, create a new OpenStack image from the virtual disk:
{% highlight sh %}
openstack image create \
  --container-format bare \
  --disk-format qcow2  \
  --file windows-disk.qcow2 \
  myvm-disk
{% endhighlight %}

The image can take a few minutes as the virtual disk is uploaded to the `glance` service.

Then, create an OpenStack volume from that image:
{% highlight sh %}
openstack volume create \
  --image myvm-disk \
  --size 60 \
  myvm-disk
{% endhighlight %}

Creating the volume can also take some time, use `openstack volume list` to check its progress.

Once the volume is create and is in the `available` state, create the final virtual machine:
{% highlight sh %}
openstack server create
  --volume myvm-disk \
  --flavor w1.small \
  --key-name yyy \
  --security-group xxx \
  myvm
{% endhighlight %}

**Notes:**
- Replace the security group `xxx` with the appropriate value for your OpenStack.
- Replace the key name `yyy` with the appropriate key name.
- If the virtual disk is an UEFI image, add the following property: `hw_firmware_type=uefi`:
{% highlight sh %}
openstack server create
  --volume myvm-disk \
  --flavor w1.small \
  --security-group xxx \
  --key-name yyy \
  --property hw_firmware_type=uefi \
  myvm
{% endhighlight %}

## Running UEFI Virtual Machines on OpenStack

Unfortunately, the OpenStack compute server (`nova`) reads the UEFI settings only from the image of the instance. And, in our case, there is no base image as the instance is directly attached to a volume.

There might be ways to read the image from the volume, but I have not found it in nova's source code.

The best was to patch the source code to read the firmware type from the instance metadata. With the virtual machines I was moving, I also had to remove the secure boot UEFI as it wouldn't boot (without configuring it, of course).

Here is the patch to apply in `/usr/lib/python3/dist-packages/nova/virt/libvirt` for OpenStack Victoria:

{% highlight diff %}
*** driver.py.orig      2021-04-12 21:14:07.000000000 +0900
--- driver.py   2021-12-22 12:39:12.982084556 +0900
***************
*** 137,143 ****

  DEFAULT_UEFI_LOADER_PATH = {
      "x86_64": ['/usr/share/OVMF/OVMF_CODE.fd',
-                '/usr/share/OVMF/OVMF_CODE.secboot.fd',
                 '/usr/share/qemu/ovmf-x86_64-code.bin'],
      "aarch64": ['/usr/share/AAVMF/AAVMF_CODE.fd',
                  '/usr/share/qemu/aavmf-aarch64-code.bin']
--- 137,142 ----
***************
*** 1331,1336 ****
--- 1330,1337 ----
              try:
                  hw_firmware_type = instance.image_meta.properties.get(
                      'hw_firmware_type')
+                 if not hw_firmware_type:
+                     hw_firmware_type = instance.get('metadata').get('hw_firmware_type')
                  support_uefi = self._check_uefi_support(hw_firmware_type)
                  guest.delete_configuration(support_uefi)
              except libvirt.libvirtError as e:
***************
*** 2010,2015 ****
--- 2011,2018 ----

          hw_firmware_type = instance.image_meta.properties.get(
              'hw_firmware_type')
+         if not hw_firmware_type:
+             hw_firmware_type = instance.get('metadata').get('hw_firmware_type')

          try:
              self._swap_volume(guest, disk_dev, conf,
***************
*** 2688,2693 ****
--- 2691,2698 ----
              if guest.has_persistent_configuration():
                  hw_firmware_type = image_meta.properties.get(
                      'hw_firmware_type')
+                 if not hw_firmware_type:
+                     hw_firmware_type = instance.get('metadata').get('hw_firmware_type')
                  support_uefi = self._check_uefi_support(hw_firmware_type)
                  guest.delete_configuration(support_uefi)

***************
*** 5637,5642 ****
--- 5642,5649 ----
                  guest.sysinfo = self._get_guest_config_sysinfo(instance)
                  guest.os_smbios = vconfig.LibvirtConfigGuestSMBIOS()
              hw_firmware_type = image_meta.properties.get('hw_firmware_type')
+             if not hw_firmware_type:
+                 hw_firmware_type = instance.get('metadata').get('hw_firmware_type')
              if caps.host.cpu.arch == fields.Architecture.AARCH64:
                  if not hw_firmware_type:
                      hw_firmware_type = fields.FirmwareType.UEFI
{% endhighlight %}

You apply it like this:
{% highlight sh %}
cd /usr/lib/python2.7/dist-packages/nova/virt/libvirt
sudo patch driver.py < driver.py.patch
sudo python -m compileall driver.py
sudo systemctl restart nova-compute.service
{% endhighlight %}

[libvirt]:          https://libvirt.org
[openstack]:        https://www.openstack.org
[openstack-client]: https://docs.openstack.org/python-openstackclient/latest
[qemu-macos]:       https://qemu.org/download/#macos
[qemu-windows]:     https://qemu/download/#windows
[virtio]:           https://wiki.libvirt.org/page/Virtio
