# Bootstrap K3s with Ansible

K3s installation is automated via Ansible. Manual steps below are kept for reference.

## Recommended: Ansible (automated)

```bash
# After terraform apply in terraform/environments/dev
export SSH_PRIVATE_KEY=~/.ssh/campaign-center-key.pem
./ansible/scripts/install-k3s.sh dev

export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
kubectl get nodes
```

See the root [README.md](../README.md) for prerequisites and troubleshooting.

## Manual install (reference)

Replace `<EIP>` with `terraform output -raw k3s_master_public_ip`.

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san <EIP> --disable servicelb" sh -
```

Join workers:

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://<master-private-ip>:6443 \
  K3S_TOKEN=<token> \
  sh -s - agent --node-ip <worker-private-ip>
```

## Reset

```bash
CONFIRM_RESET=true ./ansible/scripts/reset-k3s.sh dev
```
