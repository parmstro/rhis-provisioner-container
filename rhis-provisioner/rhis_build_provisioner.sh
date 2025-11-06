#!/bin/bash

# default to AAP 2.4
ansiblever="2.4"
version_file="./version24.txt"
version_mode="revision"
base_version_file="../rhis-base/version24.txt" 
base_inventory_version_file="inventory_version.txt"

nocache="false"
buildargs=""
ansiblecfg="/etc/ansible/ansible.cfg"
push_registry="quay.io"
push_repo="parmstro"
push_registry_login=""
push_registry_token=""

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
        -r|--push-registry)
            push_registry="$2"
            shift
            ;;
        -R|--push-repo)
            push_registry_repo="$2"
            shift
            ;;
        -u|--push-registry-login)
            push_registry_login="$2"
            shift
            ;;
        -t|--push-registry-token)
            push_registry_token="$2"
            shift
            ;; 
        -m|--version-mode)
            version_mode="$2"
            shift
            ;; 
        *)
            echo "Unknown option: $1"
            echo "Usage: rhis_build_provisioner.sh [options]"
            echo "Options:"
            echo "    --no-cache - rebuild container from scatch"
            echo "    --ansible-ver - specify the AAP API version - one of '2.4' (default) or '2.5'"
            echo "    --ansible-config path_spec - provide the path specification to the ansible.cfg file (default: /etc/ansible/ansible.cfg)"
            echo "    --push-registry - the name of the remote registry to push the final image to (default: quay.io)"
            echo "    --push-registry-repo - the name of the repo in the remote registry (default: parmstro)"
            echo "    --push-registry-login - the login for the push registry (e.g. mybot)"
            echo "    --push-registry-token - the authentication token for the push registry"
            echo "    --version-mode - increment major, minor, or revision version of the build"
            exit 1
            ;;
    esac
    shift # Shift past the option
done

build_container() {
  echo "Starting build of rhis-provisioner container version: $version for AAP version: $ansiblever"
  echo
  echo "Ensuring ansible and podman requirements are installed..."
  sudo dnf -y install ansible-core podman

  if [[ -n "$push_registry" && -n "$push_registry_login" && -n "$push_registry_token" ]]; then
    echo "Using $push_registry as the pull and push registry. Logging in."
    podman login $push_registry -u $push_registry_login -p $push_registry_token
  else
    echo "push_registry parameters not defined. Continuing with local build."
  fi

  echo "Configure sources"
  cp $ansiblecfg sources/ansible.cfg
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
    buildargs="--build-arg ANSIBLE_VER=2.5 --build-arg OS_VER=9 --build-arg RHIS_BASE_VER=$base_version --build-arg RHIS_VER=$version"
  else
    buildargs="--build-arg ANSIBLE_VER=2.4 --build-arg OS_VER=9 --build-arg RHIS_BASE_VER=$base_version --build-arg RHIS_VER=$version"
  fi

  if [[ $nocache == "true" ]]; then
    buildargs+=" --no-cache"
  fi

  echo $buildargs

  podman build $buildargs -t rhis-provisioner-9-$ansiblever:$version .
  podman tag localhost/rhis-provisioner-9-$ansiblever:$version rhis-provisioner-9-$ansiblever:latest

  if [[ $push_registry && $push_registry_login && $push_registry_token ]]; then
    podman login -u=$push_registry_login -p=$push_registry_token $push_registry
    podman tag localhost/rhis-provisioner-9-$ansiblever:$version $push_registry/$push_repo/rhis-provisioner-9-$ansiblever:$version
    podman tag localhost/rhis-provisioner-9-$ansiblever:$version $push_registry/$push_repo/rhis-provisioner-9-$ansiblever:latest
    podman push $push_registry/$push_repo/rhis-provisioner-9-$ansiblever:$version
    podman push $push_registry/$push_repo/rhis-provisioner-9-$ansiblever:latest
  fi
}

get_base_version() {
  if [[ $ansiblever == "2.5" ]]; then
    base_version_file="../rhis-base/version25.txt" 
  else
    base_version_file="../rhis-base/version24.txt" 
  fi
  current_base_version=$(cat $base_version_file)
  echo "${current_base_version}"
}

increment_version() {
  if [[ $ansiblever == "2.5" ]]; then
    version_file="./version25.txt"
    base_version_file="../rhis-base/version25.txt" 
  else
    version_file="./version24.txt"
    base_version_file="../rhis-base/version24.txt" 
  fi
  current_version=$(cat $version_file)
  base_vserion=$(cat $base_version_file)

  IFS='.' read -r major minor revision <<< "$current_version"
  case "$1" in
    "major")
        major=$((major + 1))
        minor=0
        revision=0
        ;;
    "minor")
        minor=$((minor + 1))
        revision=0
        ;;
    "revision")
        revision=$((revision + 1))
        ;;
    *)
        echo "Invalid mode"
        exit 1
  esac

  # Create the new version string
  new_version="$major.$minor.$revision"
  echo "${new_version}"
}

update_version() {
  echo $version > $version_file
}

base_version=$(get_base_version)
version=$(increment_version "$version_mode")
# Run main commands
build_container

# Check the exit status of the main commands
if [[ $? -eq 0 ]]; then
    # If build was successful, increment the revision
    echo "Successfully built $version - Updating version file."
    update_version
else
    echo "One or more build commands failed. Version file not updated."
fi
