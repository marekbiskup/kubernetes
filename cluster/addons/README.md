# Cluster add-ons

Cluster add-ons are Services and Replication Controllers (with pods) that are
shipped with the kubernetes binaries and whose update policy is also consistent
with the update of kubernetes cluster.

On the clusterm the addons are kept in ```/usr/local/bin/kubectl``` on the master node, in yaml files
(json is not supported at the moment).
Each add-on must specify the following label: ````kubernetes.io/cluster-service: true````.
Yaml files that do not define this label will be ignored.

# Add-on update

To update add-ons, just update the contents of ```/usr/local/bin/kubectl```
directory with the desired definition of add-ons. Then the system will take care
of:

1. Removing the objects from the API server whose manifest was removed.
  1. This is done for add-ons in the system that do not have a manifest file with the
     same name.
1. Creating objects from new manifests
  1. This is done for manifests that do not correspond to existing API objects
     with the same name
1. Updating objects whose name is the same, but the data of the object changed
  1. This update is currently not implemented.


[![Analytics](https://kubernetes-site.appspot.com/UA-36037335-10/GitHub/cluster/addons/README.md?pixel)]()
