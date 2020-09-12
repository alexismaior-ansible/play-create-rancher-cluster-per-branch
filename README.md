Ansible Playbook - Create Rancher Cluster per Branch
=========

This playbook is used to create and delete kubernete clusters in Rancher. It was developed to be integrated with drone.io but can be easily used standalone.

Command to execute the creation pipeline
```
ansible-playbook -i sof.vmware.yaml play-create-cluster.yaml --vault-id drone@prompt --extra-vars "rancher_clustername=devhellotest"
```

Command to execute the deletion pipeline
```
ansible-playbook -i sof.vmware.yaml play-delete-cluster.yaml --vault-id drone@prompt --extra-vars "rancher_clustername=devhellotest"
```

Requisites
------------

Python pywinrm modules for integration with Windows Server (DNS), pyvmomi for integration with VMware and vsphere-automation-sdk-python for integration with VMware tags must be installed.

Variabels
--------------
The variables are defined in the following places:

- Var folder, for integration variables and standard definitions
- group_vars folder, for user variables and password for connecting to vmware_vars
- Host_vars folder, for user variables and password for connection to psdc01.sof.intra
- The rancher_clustername variable is the main variable passed by the drone. It receives the value of the current branch.

```
ansible-vault encrypt_string --vault-id drone@prompt '12345' --name 'ansible_password'
```

The command will ask for a password, which is the password of the drone user, created for this 'vault', as an encryption user.
During the execution of the playbook, it is necessary to pass on the password that was entered at the prompt.


VMware Dynamic Inventory
=========

The main strategy of the playbook is to use VMs that are "available" to be provisioned in a k8s cluster. For this, the VMware TAG resource was used. For all VMs in the Kubernetes / dev folder, initially they all received the "available" tag. As they are allocated to a cluster, they are tagged with the cluster name (in this case, the branch).

Ansible has a dynamic inventory feature, using the vmware_vm_inventory plugin. It communicates with vcenter and creates an "inventory" grouped by these tags. That is, at a given time, the inventory will bring the VMs grouped by cluster and those VMs that are available for a new cluster.


Playbook Workflow
=========

The playbook uses some ansible roles, available on ansible-galaxy.

```
jtyr.ansible_vmware_vm_provisioning - Role responsible for creating and configuring VMs on vcenter

ericsysmin.docker.docker - Role responsible for installing Docker on the VM.

andrewrothstein.kubectl - Role responsible for installing Kubectl.

gantsign.helm - Role responsible for installing the helm.

alexismaior.ansible_role_manage_rancher_cluster - Role that interacts with the rancher API for creating the cluster
```

Initially the playbook looks for whether the rancher_clustername already exists in the dynamic inventory. If not, it is possibly because the cluster does not exist. If the group in the inventory exists, it uses the hosts defined for execution.

The ultimate goal is that, if a cluster already exists, it will verify that the nodes defined for that cluster are healthy and active. Otherwise, he tries to recreate them in Rancher.
If there is no cluster, it will create from 3 random VMs in the "available" group.

At the end, the playbook will execute the createTestEnv.sh which clones configmap and secrets from staging namespace and deploys in the new cluster helm charts of the same version as in staging.
