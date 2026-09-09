# Teleport assignement
Teleport K8s deployment assignment

This repository is the implementation of the technical assignment for the Senior Field Engineer role.
The requirements is to build a demo with a live K8s cluster installed with kubeadm, comprised of a single master, and two worker nodes, plus an nginx-based web-site as a workload on top of the cluster.

Deployment will be done in an AWS cloud on 3 CentOS hosts. 
No HA considerations as separate zones are taken, as the cluster will only have one master, hence no real HA is possible. However, the concept can be implemented by extending the node count an spreading the nodes throughout the different zones.
Nodes are deployed in the same subnet, and the security group allowing the full access between the nodes, web-access to the web server, API access to the control-plane, and ssh from the specified host is configured.

## Prepare nodes and deploy Kubernetes

After spinning up the instances, `prep_node.sh` script to be executed on each instance as a preparation step to get them configured up to specs in order to be able to install Kubernetes cluster via kubeadm. This involves disabling swap, SELinux, and tunning kernel parameters. Also, containerd, kubeadm, kubelet, and kubectl are installed.
Once the nodes are prepared, one of the nodes - the one to serve as a control-plane, has to be initialized with the following kubeadm command:

```
kubeadm init --apiserver-advertise-address=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4` --apiserver-cert-extra-sans=`curl -s http://169.254.169.254/latest/meta-data/public-ipv4` --pod-network-cidr=10.244.0.0/16
```

DNS names can be added to '--apiserver-cert-extra-sans' separated by comma, for access, for which you can point a DNS API-access entry to the IP of control-plane as an A record:

```
kubeadm init --apiserver-advertise-address=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4` --apiserver-cert-extra-sans=k8s.ruslidze.com,`curl -s http://169.254.169.254/latest/meta-data/public-ipv4` --pod-network-cidr=10.244.0.0/16

```

The `--pod-network-cidr=10.244.0.0/16` is used as this is the default CIDR for Flannel installed as a next step.
This will initiallize the control-plane node, after which you'd have to deploy a pod network, for example Flannel:

```
export KUBECONFIG=/etc/kubernetes/admin.conf
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

## Configure AWS LoadBalancer Controller, Cert-manager, and NGINX-Ingress Controller

For external access to services, the AWS Load Balancer controller was implemented as described in `https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/`. This also requires some work on AWS side:
* tagging the subnets where the nodes are deployed (`kubernetes.io/cluster/kubernetes = shared` and `kubernetes.io/role/elb = 1`)
* creating and IAM policy per `https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/docs/install/iam_policy.json`
* creating a role associated with the policy and binding it to the instances (In IAM Management -> Roles -> Create role -> AWS service -> EC2 -> EC2 -> Next -> Use existing policy -> your policy)

You also have to patch the nodes with the explicit AZ and instance ID in order to make this setup work. Both can be retrieved from the AWS instance details, and the node name from `kubectl get nodes` output. Example inputs:  "aws:///use1-az4/i-01388244a33f07830". The patch command shold be executed for each node and will look like below:

```
    kubectl patch node <node name> -p '{"spec":{"providerID":"aws:///<AZ>/<instance ID>"}}'
```


Install cert manager:
```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml
```
Download, edit (controller documentation recommends deleting the ServiceAccount section), and apply LBC spec from https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/#apply-yaml:
```
    wget https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v3.5.0/v3_5_0_full.yaml
    vi v3_5_0_full.yaml
    kubectl apply -f v3_5_0_full.yaml
```

Additional fix to make LB work is needed in the form of aws-lb-controller-sa.yaml pointing to the AWS role used above, follwed by a deployment restart
```
   kubectl apply -f aws-lb-controller-sa.yaml
   kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

It is important to note, that with this setup, any LoadBalancer type services would have to have annotations in order to make the AWS LoadBalancer controller work. Something as follows to be added in the specs:

```
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: test-namespace
  annotations:
    # Triggers the AWS Load Balancer Controller instead of the legacy in-tree provider
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

or patching:

```
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-type":"external","service.beta.kubernetes.io/aws-load-balancer-nlb-target-type":"instance","service.beta.kubernetes.io/aws-load-balancer-scheme":"internet-facing"}}}'
```

Apply and patch nginx ingress controller:

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml
kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-type":"external","service.beta.kubernetes.io/aws-load-balancer-nlb-target-type":"instance","service.beta.kubernetes.io/aws-load-balancer-scheme":"internet-facing"}}}'
```

At this point you can reploint DNS web-access entry to the newly created LoadBalancer.

## Configure user access and RBAC

Generate key, csr, and crt signed by the control-planes CA on the control plane as root user:

```
cd /tmp
openssl genrsa -out ruslan.key 2048
openssl req -new -key ruslan.key -out ruslan.csr -subj "/CN=ruslan/O=dev/O=ruslidze.com"
openssl x509 -req -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -days 730 -in ruslan.csr -out ruslan.crt
chmod 644 ./ruslan.*
```

Download to your client machine, create a user and a context:

```
scp -i <your .pem private ssh key> 'ec2-user@<IP>:/tmp/ruslan.*' ./
kubectl config set-credentials ruslan --client-certificate=ruslan.crt --client-key=ruslan.key
kubectl config set-context ruslan-kubernetes --cluster=kubernetes --user=ruslan
```

Create a new namespace, role, and role binding for the new user:

```
kubectl apply -f RBAC/test_role.yaml
```

Switch context to your newly created one for the new user:

```
kubectl config use-context ruslan-kubernetes 
```

And deploy the workload in the new namespace as the new user:

```
kubectl apply -f workload/nginx.yaml
kubectl apply -f workload/prodIssuer.yaml
kubectl apply -f workload/ingress.yaml 
```


## Extra: Installing ArgoCD and running an nginx on top

Install ArgoCD and patch the service for access:

```
kubectl create namespace argocd 
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-type":"external","service.beta.kubernetes.io/aws-load-balancer-nlb-target-type":"instance","service.beta.kubernetes.io/aws-load-balancer-scheme":"internet-facing"}}}'
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```
Fetch default admin password for UI:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```
Connect repo in UI by navigating to Settings -> Repositories -> "+ CONNECT REPO" -> "VIA SSH" -> provide name, project, repo URL (git@github.com:ruslidze/TeleportAssignement.git) and a private ssh key to access the repo, stored in ~/.ssh -> CONNECT

In the Applications -> "+ NEW APP" fill in the basic fields.
Add SOURCE repo and set the path to workload1 directory (workload is for manual execution).
Add https://kubernetes.default.svc as a destination and test-namespace as a namespace.

CREATE

## Extra: Installing Teleport

The first part of below is based on https://goteleport.com/docs/get-started/deploy-community/

1. Spin up an instance with ami-041561b526a948565 as preinstalled AMI with teleport 18.11 as per https://goteleport.com/docs/installation/single-machine/amazon-ec2/ and apply fresh config 

```
sudo rm -f /etc/teleport.yaml
sudo teleport configure -o file --acme --acme-email=ruslidze+teleport@gmail.com --cluster-name=teleport.ruslidze.com
```

2. Configure DNS pointing both entries to an external IP of the instance. Make sure security group allows port 443 from anywhere as the service needs to have access for domain verification from Let's Encrypt. By now you should have access to the Web UI.

3. Create a new user:

```
sudo tctl users add teleport-admin --roles=editor,access,auditor --logins=root,ubuntu,ec2-user
```

Visit the link generated by the above command, add the password and MFA (Google Authenticater should work)
Now you should be able to see your resources, of which you should only have a single server where the teleport is running.

Next, we are connecting an infrastructure as per https://goteleport.com/docs/get-started/connect/ "Add New" and follow trhe prompts. Adding Kubernetes cluster requires Helm installed on your local machine. Follow the prompts and add the cluster.