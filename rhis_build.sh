#!/bin/bash
version=$(<version.txt)
cp ansible.cfg sources/ansible.cfg
cp ansible.cfg.clean sources/ansible.cfg.clean
cp podman_commands.txt sources/podman_commands.txt
cp rhis-builder_sample_commands.txt sources/rhis-builder_sample_commands.txt 
cp add_softlinks.yml sources/add_softlinks.yml
cp remove_softlinks.yml sources/remove_softlinks.yml
cp README.md sources/README.md

if [ $1 == --no-cache ]; then
  podman build --no-cache -t rhis-provisioner-9:$version .
else
  podman build -t rhis-provisioner-9:$version .
fi

podman tag localhost/rhis-provisioner-9:$version rhis-provisioner-9:latest