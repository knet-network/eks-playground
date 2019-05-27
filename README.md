eks-playground
==============

# Requirements 
- terraform >= 0.12
- aws credentials and profile
- IAMFullAccess
- EKSFullAccess
- EC2FullAccess
- Route53FullAccess

# Usage
```bash
terraform init
terraform apply -auto-approve

aws eks update-kubeconfig --name playground

# note that this will add provisioned nodes which might be not what you want
# when testing stuff
kubectl apply -f aws-auth.yaml 
```