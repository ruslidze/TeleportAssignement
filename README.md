# TeleportAssignement
Teleport K8s deployment assignment

This repository is the implementation of the technical assignment for the Senior Field Engineer role.
The requirements is to build a demo with a live K8s cluster installed with kubeadm, comprised of a single master, and two worker nodes, plus an nginx-based web-site as a workload on top of the cluster.

Deployment will be done in an AWS cloud on 3 CentOS hosts. 
No HA considerations as separate zones are taken, as the cluster will only have one master, hence no real HA is possible. However, the concept can be implemented by extending the node count an spreading the nodes throughout the different zones.
Nodes are deployed in the same subnet, and the security group allowing the full access between the nodes, web-access to the web server, API access to the control-plane, and ssh from the specified host is configured.

###nodes FW is a consideration


After spinning up the instances, `prep_node.sh` script to be executed on each instance as a preparation step to get them configured up to specs in order to be able to install Kubernetes cluster via kubeadm. This involves disabling swap, SELinux, and tunning kernel parameters. Also, containerd, kubeadm, kubelet, and kubectl are installed.
Once the nodes are prepared, one of the nodes - the one to serve as a control-plane, has to be initialized with the following kubeadm command:

```
kubeadm init --apiserver-advertise-address=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4` \ 
	--apiserver-cert-extra-sans=<DNS>,`curl -s http://169.254.169.254/latest/meta-data/public-ipv4` \ 
	--pod-network-cidr=<CIDR>
```

This will initiallize the control-plane node, after which you'd have to deploy a pod network, for example Flannel:

```
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

With that done, you should be ready to add the worker nodes to the cluster. An example command might look like this:

```
kubeadm join 172.31.12.34:6443 --token u27dng.bb8l981234567890 \
	--discovery-token-ca-cert-hash sha256:123456789009d9ac4b0e5ccc6ca476909550c7280a56aba608f0c9fb7a9932e3 
```

but, please refer to the output of the `kubeadmin init` as the security tokens are unique for each setup.  

To get access to the cluster via the API, please copy over the `/etc/kubernetes/admin.conf` from the control plane to your local `$HOME/.kube/config` and run 

```
kubectl config set-cluster kubernetes --server=https://<DNS or IP>>:6443
```



For external access to services, the AWS Load Balancer controller was implemented as described in `https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/`. This also requires some work on AWS side:
* tagging the subnets
* creating and IAM policy per `https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/docs/install/iam_policy.json`
* creating a role associated with the policy and binding it to the instances
* Install cert manager:
```
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.3/cert-manager.yaml
```
* Download and apply LBC spec from https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/#apply-yaml:
```
    wget https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v3.5.0/v3_5_0_full.yaml
    kubectl apply -f v3_5_0_full.yaml
```

Additional fix to make LB work is needed in the form of aws-lb-controller-sa.yaml pointing to the AWS role used above, follwed by a deployment restart
```
   kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```


