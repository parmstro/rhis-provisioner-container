#!/bin/bash
version=$(<version.txt)
ansiblever="2.4"
nocache="false"
buildargs=""
ansiblecfg="/etc/ansible/ansible.cfg"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -a|--ansible-ver)
            ansiblever="$2"
            shift # Shift past the value
            ;;
        -n|--no-cache)
            nocache="true"
            #shift # Shift past the value
            ;;
        -c|--ansible-config)
            ansiblecfg="$2"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift # Shift past the option
done

sudo dnf -y install ansible-core podman 
podman login registry.redhat.io

cp $ansiblecfg sources/ansible.cfg
cp ansible.cfg.clean sources/ansible.cfg.clean
cp podman_commands.txt sources/podman_commands.txt
cp rhis-builder_sample_commands.txt sources/rhis-builder_sample_commands.txt 
cp add_softlinks.yml sources/add_softlinks.yml
cp remove_softlinks.yml sources/remove_softlinks.yml
cp README.md sources/README.md

echo
echo "Running 'podman build' with the following parameters:"
echo
echo "ansible-ver: $ansiblever"
echo "no-cache: $nocache"
echo

if [[ $ansiblever == "2.5" ]]; then
  buildargs="--build-arg ANSIBLE_VER=2.5"
else
  buildargs="--build-arg ANSIBLE_VER=2.4"
fi

if [[ $nocache == "true" ]]; then
  buildargs+=" --no-cache"
fi

podman build $buildargs -t rhis-provisioner-9-$ansiblever:$version .
podman tag localhost/rhis-provisioner-9-$ansiblever:$version rhis-provisioner-9-$ansiblever:latest
