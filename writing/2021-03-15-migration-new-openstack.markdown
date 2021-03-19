---
layout: post
title:  "Migrating Instances toa new OpenStack"
author: Gildas Cherruel
date:   2021-03-15 12:30:00 +0900
tags: openstack kvm libvirt migration
---
At my company, we just moved to a new location. That gave IT the opportunity to get rid of hardware. And THAT gave me the opportunity to upgrade our OpenStack cloud. I was able to change all components to far superior hardware.

That also meant, I had to migrate images, flavors, instances, etc to the new OpenStack environment.

Migrating the instance proved to be quite a challenge as there are more than one scenario to cover:
- the instance has its root virtual disk stored on a compute node,
- the instance has its root virtual disk stored on a block storage node,
- the instance has a data virtual disk stored on a block storage node.

In all of these situations, we need to follow these steps:
1. Export the instance virtual disks from the old OpenStack
2. Transfer the virtual disks to the new OpenStack
3. Import the virtual disks to a new instance in the new OpenStack

## Export the instance disks

The first step is to stop the instance (called here `myvm`), so we can transfer it in a stable state.

```console
openstack server stop myvm
```

For good measure, let's check the instance and write down the flavor, image, security groups, properties that we will need to use on the new OpenStack:
```console
openstack server show myvm
```

### Root disk on a compute node

First, we need to take a snapshot of the instance:
```console
openstack server image create --name myvm-snapshot myvm
```
And wait....

If we are not on the glance server, we should retrieve the image file:
```console
os image save --file myvm-snapshot.qcow2 myvm-snapshot
```

If we are on the glance server and it uses a file backend, actually, the qcow2 file of the image is already here, so we can save time and disk:
```console
ln -s /var/lib/glance/images/$(openstack show image -c id -f value myvm-snapshot) myvm-snapshot.qcow2
```

### Root disk on a storage node

#### Non detachable

If we cannot detach the volume (let's call it `myvm-system`) from the instance, we need to make a snapshot volume:
```console
openstack volume snapshot create --volume myvm-system --force myvm-system-snapshot
```
That can ake a while, so we (again) wait...

Once it is ready, we can create another volume:
```console
openstack volume create myvm-temp \
  --snapshot myvm-system-snapshot \
  --size $(openstack volume show -c size -f value myvm-system)
```

Now, we can finally get an image from the volume:
```console
openstack image create myvm-snapshot --volume myvm-temp
```

We can now download the image file like we did previously:
```console
os image save --file myvm-snapshot.raw myvm-snapshot
```

**Note:**
- Here I am not sure if we can safely convert the raw disk into a qcow2.
- Depending on the original storage, we might even be able to get a qcow2 directly.

#### Detachable

If we can detach the volume from the instance, we just need to do:
```console
openstack server remove volume myvm myvm-system
```

And get an image from the volume:
```console
openstack image create myvm-snapshot --volume myvm-system
```

We can now download the image file like we did previously:
```console
os image save --file myvm-snapshot.raw myvm-snapshot
```

**Note:**
- Here I am not sure if we can safely convert the raw disk into a qcow2.
- Depending on the original storage, we might even be able to get a qcow2 directly.

### Data disk on a storage node

Once the system disk is saved by one of the two methods previously described, you can download the data volume.

First we need to remember the volume size:
```console
openstack volume show -c size -f value myvm-data
```

Then we can remove the volume from its instance:
```console
openstack server remove volume myvm myvm-data
```

Then, we need to make an image out of it:
```console
openstack image create myvm-data --volume myvm-data
```

And get the file:
```console
os image save --file myvm-data.raw myvm-data
```

**Note:**
- Here I am not sure if we can safely convert the raw disk into a qcow2.
- Depending on the original storage, we might even be able to get a qcow2 directly.

## Transfer the instance disks

Here, we can use any file transfer we deemed necessary: scp, rsync, ftp, USB stick, etc.

## Import the instance disks

When you import the instance disks to the new OpenStack you can choose to put the root disk on a compute node or on a storage node. This choice is independent of what was running on the old OpenStack.

First, you should import the virtual disk as an image:
```console
openstack image create \
  --container-format bare \
  --disk-format qcow2 \
  --file myvm-snapshot.qcow2 \
  myvm-snapshot
```

### Root disk on a compute node

In that case, you can just instantiate the server from the image (use the values you wrote down previously):

```console
openstack server create \
  --image myvm-snapshot \
  --flavor m1.tiny \
  --network mynet \
  --security-group allow_ssh \
  --property key=value \
  --key-name mykey \
  myvm
```

### Root disk on a storage node

First we need to create a volume from the image (`xx` should be replaced by the size in GB from the export steps):
```console
openstack volume create \
  --image myvm-snapshot \
  --size xx \
  myvm-system
```

And wait....

Finally, we instantiate the server from the volume:
```console
openstack server create \
  --volume myvm-system \
  --flavor m1.tiny \
  --network mynet \
  --security-group allow_ssh \
  --property key=value \
  --key-name mykey \
  myvm
```

### Data disk on a storage node

First, we need to create a volume from the image (`xx` should be replaced by the size in GB from the export steps):
```console
openstack volume create \
  --image myvm-snapshot \
  --size xx \
  myvm-data
```

And wait....

Finally, we can attach the volume to the instance:
```console
openstack server add volume myvm myvm-data
```

### Update the database

If we need to update the image, we can do this:

```console
sudo mysql -e "update nova.instances set image_ref = '$(openstack image show -f value -c id windows-server-2019)'  where uuid = '$(openstack server show -f value -c id labconsole)'"
```

If we need to update the owner, we can do this:

```console
sudo mysql -e "update nova_api.instance_mappings set user_id = '$(openstack user show -f value -c id --domain XYZ john.doe)'  where instance_uuid = '$(openstack server show -f value -c id labconsole)'"
sudo mysql -e "update nova.instances set user_id = '$(openstack user show -f value -c id --domain XYZ john.doe)'  where uuid = '$(openstack server show -f value -c id labconsole)'"
```

Changing the key pair.... trying:
```sql
select name,user_id,fingerprint,public_key
  from nova_api.key_pairs;

update nova.instances
  set key_name = 'john.doe'
  where uuid = 'e9b476f1-5ad8-493d-98d5-d774b5158bc9';
```
