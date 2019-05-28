eks-playground
==============

[![Build Status](https://codebuild.eu-central-1.amazonaws.com/badges?uuid=eyJlbmNyeXB0ZWREYXRhIjoicFlxTVNzT1VpTTJ6QWt6U2JPdHd6Y2xlakljUkh0eHd6RHo4YVhXT1drcFBJa05Pc3JCcnRlQWt6TjlST0ZkWkZmeDNwYmxlREVOQ0FONVdlVGVEVzFFPSIsIml2UGFyYW1ldGVyU3BlYyI6IjhUYklFc1FPdCswa0piT0MiLCJtYXRlcmlhbFNldFNlcmlhbCI6MX0%3D&branch=master)](https://codebuild.eu-central-1.amazonaws.com/badges?uuid=eyJlbmNyeXB0ZWREYXRhIjoicFlxTVNzT1VpTTJ6QWt6U2JPdHd6Y2xlakljUkh0eHd6RHo4YVhXT1drcFBJa05Pc3JCcnRlQWt6TjlST0ZkWkZmeDNwYmxlREVOQ0FONVdlVGVEVzFFPSIsIml2UGFyYW1ldGVyU3BlYyI6IjhUYklFc1FPdCswa0piT0MiLCJtYXRlcmlhbFNldFNlcmlhbCI6MX0%3D&branch=master)


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
