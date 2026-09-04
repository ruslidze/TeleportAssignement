# TeleportAssignement
Teleport K8s deployment assignment

This repository is the implementation of the technical assignment for the Senior Field Engineer role.
The requirements is to build a demo with a live K8s cluster installed with kubeadm, comprised of a single master, and two worker nodes, plus an nginx-based web-site as a workload on top of that cluster .

Deployment will be done in an AWS cloud on 3 free-tier Rocky Linux hosts, in a single VPC. 
No HA considerations as separate zones are taken, as the cluster will only have one master, hence no real HA is possible. However, the concept can be implemented by extending the node count an spreading the nodes throughout the different zones.
Nodes are deployed in the same subnet, and the security group allowing the full access between the nodes, web-access to the web server, and ssh from the specified host is configured.

###nodes FW is a consideration
