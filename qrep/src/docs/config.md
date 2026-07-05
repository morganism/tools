Configuration precedence (lowest → highest):

1. /etc/qrep/qrep-config.yaml
2. ~/.config/qrep/qrep-config.yaml (or $XDG_CONFIG_HOME)
3. ~/.qrep-config.yaml
4. .qrep-config.yaml

Later files override earlier ones. Hashes deep-merge; scalars replace.
