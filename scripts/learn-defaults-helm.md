# Learn Helm Defaults - Vault Chart

Useful for seeing what is enabled/disabled by default in a Helm chart.

Removes commented out material containing documentation and null values so you can
see at a glance what is on/off - good starting point in some scenarios.

```
helm show values oci://registry-1.docker.io/bitnamicharts/vault --version 0.4.3 | grep -vE "^#|^$" | grep -B 3 "enabled:" > vault-learn.yaml
```
