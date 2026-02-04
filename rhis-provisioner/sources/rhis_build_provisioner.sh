#!/bin/bash

# default to AAP 2.4
ansiblever="2.4"
# Inuit word for packed snow used for building :-)
build="aniyu"
version_file="./version24.txt"
version_mode="revision"
base_version_file="../rhis-base/version24.txt" 
rhis_schema_version_file="rhis-schema-version.txt"

nocache="false"
buildargs=""
ansiblecfg="/etc/ansible/ansible.cfg"

pull_registry="quay.io"
pull_registry_repo="parmstro"
pull_registry_login=""
pull_registry_token=""

push_registry="quay.io"
push_registry_repo="parmstro"
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
        -p|--pull-registry)
            pull_registry="$2"
            shift
            ;;
        -P|--push-registry)
            push_registry="$2"
            shift
            ;;
        -r|--pull-registry-repo)
            pull_registry_repo="$2"
            shift
            ;;
        -R|--push-registry-repo)
            push_registry_repo="$2"
            shift
            ;;
        -u|--pull-registry-login)
            pull_registry_login="$2"
            shift
            ;;
        -U|--push-registry-login)
            push_registry_login="$2"
            shift
            ;;
        -t|--pull-registry-token)
            pull_registry_token="$2"
            shift
            ;; 
        -T|--push-registry-token)
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
            echo ""
            echo "    --pull-registry - the name of the remote registry to pull the base image from (default: quay.io)"
            echo "    --pull-registry-repo - the name of the repo in the remote pull registry (default: parmstro)"
            echo "    --pull-registry-login - the login for the pull registry (e.g. mybot)"
            echo "    --pull-registry-token - the authentication token for the pull registry"
            echo ""
            echo "    --push-registry - the name of the remote registry to push the final image to (default: quay.io)"
            echo "    --push-registry-repo - the name of the repo in the remote registry (default: parmstro)"
            echo "    --push-registry-login - the login for the push registry (e.g. mybot)"
            echo "    --push-registry-token - the authentication token for the push registry"
            echo ""
            echo "    --version-mode - increment major, minor, or revision version of the build"
            echo "Specifying 'localhost' for either the pull or push registry will ignore the corresponding repo option."
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

  if [[ -n "$pull_registry" && -n "$pull_registry_repo" ]]; then
    echo "Using $pull_registry as the pull registry. Logging in."
    if [[ -n "$pull_registry_login" && -n "$pull_registry_token" ]]; then
      echo "$pull_registry requires login. Logging in with provided credentials."
      podman login $pull_registry -u $pull_registry_login -p $pull_registry_token
    fi
    echo "Setting pull path"
    pull_path="$pull_registry/$pull_registry_repo"
  else
    echo "pull_registry parameters not defined. Continuing with localhost."
    pull_path="$pull_registry"
  fi

  if [[ -n "$push_registry" && -n "$push_registry_login" && -n "$push_registry_token" ]]; then
    echo "Using $push_registry as the push registry. Logging in."
    podman login $push_registry -u $push_registry_login -p $push_registry_token
  else
    echo "push_registry parameters not defined. Continuing with local build."
  fi

  schema_version=$(cat $rhis_schema_version_file)

  echo "Configure sources"
  cp $ansiblecfg sources/ansible.cfg
  cp ansible.cfg.clean sources/ansible.cfg.clean
  cp configure_rhis_builder.yml sources/configure_rhis_builder.yml
  cp rhis-builder_sample_commands.txt sources/rhis-builder_sample_commands.txt 
  cp *.sh sources/
  cp README.md sources/README.md

  cp ipareplica_test_patch.py sources/ipareplica_test_patch.py

  echo
  echo "Running 'podman build' with the following parameters:"
  echo
  echo "build: $build"
  echo "ansible-ver: $ansiblever"
  echo "no-cache: $nocache"
  echo

  if [[ $ansiblever == "2.5" ]]; then
    buildargs="--build-arg ANSIBLE_VER=2.5 --build-arg OS_VER=9 --build-arg RHIS_BASE_VER=$base_version --build-arg RHIS_VER=$version --build-arg RHIS_SCHEMA_VER=$schema_version --build-arg RHIS_BUILD=$build --build-arg PULL_PATH=$pull_path"
  else
    buildargs="--build-arg ANSIBLE_VER=2.4 --build-arg OS_VER=9 --build-arg RHIS_BASE_VER=$base_version --build-arg RHIS_VER=$version --build-arg RHIS_SCHEMA_VER=$schema_version --build-arg RHIS_BUILD=$build --build-arg PULL_PATH=$pull_path"
  fi

  if [[ $nocache == "true" ]]; then
    buildargs+=" --no-cache"
  fi

  echo $buildargs

  podman build $buildargs -t rhis-provisioner-9-$ansiblever:$version .
  podman tag localhost/rhis-provisioner-9-$ansiblever:$version rhis-provisioner-9-$ansiblever:latest

  if [[ $push_registry && $push_registry_login && $push_registry_token ]]; then
    podman login -u=$push_registry_login -p=$push_registry_token $push_registry
    podman tag localhost/rhis-provisioner-9-$ansiblever:$version $push_registry/$push_registry_repo/rhis-provisioner-9-$ansiblever:$version
    podman tag localhost/rhis-provisioner-9-$ansiblever:$version $push_registry/$push_registry_repo/rhis-provisioner-9-$ansiblever:latest
    podman push $push_registry/$push_registry_repo/rhis-provisioner-9-$ansiblever:$version
    podman push $push_registry/$push_registry_repo/rhis-provisioner-9-$ansiblever:latest
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

get_base_version_file() {
  if [[ $ansiblever == "2.5" ]]; then
    base_version_file="../rhis-base/version25.txt" 
  else
    base_version_file="../rhis-base/version24.txt" 
  fi
  echo "${base_version_file}"
}

get_rhis_version() {
  if [[ $ansiblever == "2.5" ]]; then
    rhis_version_file="./version25.txt" 
  else
    rhis_version_file="./version24.txt" 
  fi
  current_version=$(cat $rhis_version_file)
  echo "${current_version}"
}

get_rhis_version_file() {
  if [[ $ansiblever == "2.5" ]]; then
    rhis_version_file="./version25.txt" 
  else
    rhis_version_file="./version24.txt" 
  fi
  echo "${rhis_version_file}"
}

increment_version() {
  version_file=$(get_rhis_version_file)
  base_version_file=$(get_base_version_file) 
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
  echo $version > $(get_rhis_version_file)
}

base_version=$(get_base_version)
version=$(increment_version "$version_mode")
build=$(cat ../build.txt)

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
