#!/bin/bash
version=$(<version.txt)
ansiblever="2.4"
nocache="false"
buildargs=""

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
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift # Shift past the option
done

sudo dnf -y install ansible-core podman 
podman login registry.redhat.io

cp ansible.cfg sources/ansible.cfg
cp ansible.cfg.clean sources/ansible.cfg.clean
cp add_softlinks.yml sources/add_softlinks.yml
cp rhis-builder_sample_commands.txt sources/rhis-builder_sample_commands.txt 
cp build_idm_primary.sh sources/build_idm_primary.sh
cp build_idm_replicas.sh sources/build_idm_replicas.sh
cp build_sat_primary_connected.sh sources/build_sat_primary_connected.sh
cp build_test_hosts.sh sources/build_test_hosts.sh
cp destroy_test_hosts.sh sources/destroy_test_hosts.sh
cp build_aap_controller24.sh sources/build_aap_controller24.sh
cp build_aap_hub24.sh sources/build_aap_hub24.sh
cp README.md sources/README.md

cp ipareplica_test_patch.py sources/ipareplica_test_patch.py

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
