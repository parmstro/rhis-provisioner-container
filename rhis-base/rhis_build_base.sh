#!/bin/bash

# default to AAP 2.4
ansiblever="2.4"
version_file="./version24.txt"
version_mode="revision"

nocache="true"
buildargs=""
ansiblecfg="/etc/ansible/ansible.cfg"
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
        -h|--help)
            echo "Usage: rhis_build_base.sh [options]"
            echo "Options:"
            echo "    --no-cache - rebuild container from scatch"
            echo "    --ansible-ver - specify the AAP API version - one of '2.4' (default) or '2.5'"
            echo "    --ansible-config path_spec - provide the path specification to the ansible.cfg file (default: /etc/ansible/ansible.cfg)"
            echo "    --push-registry - the name of the remote registry to push the final image to (default: quay.io)"
            echo "    --push-registry_repo - the name of the repo in the remote registry to push the final image to (default: parmstro)"
            echo "    --push-registry-login - the login for the push registry (e.g. mybot)"
            echo "    --push-registry-token - the authentication token for the push registry"
            echo "    --version-mode - increment major, minor, or revision version of the build"
            echo ""
            echo "If push-registry values are not provided, only a local build will be created."
            echo "Build always pulls registry.redhat.io/ubi9:latest"
            echo "You will be asked to login to registry.redhat.io if you are not already logged in."
            exit 1
            ;;
        *)
            echo "Unknown option: $1"
            ech0 "use -h | --help for a list of allowable options"
    esac
    shift # Shift past the option
done

build_container() {
  echo "Starting build of rhis-base container version: $version for AAP version: $ansiblever"
  echo
  echo "Ensuring ansible and podman requirements are installed..."
  sudo dnf -y install ansible-core podman

  echo "Using registry.redhat.io as the pull registry"
  podman login registry.redhat.io

  if [[ -n "$push_registry" && -n "$push_registry_login" && -n "$push_registry_token" ]]; then
    echo "Using $push_registry as the push registry"
    podman login $push_registry -u $push_registry_login -p $push_registry_token
  else
    echo "push_registry parameters not defined. Continuing with local build."
  fi

  rm -f sources/*
  cp $ansiblecfg sources/ansible.cfg
  cp ansible.cfg.clean sources/ansible.cfg.clean
  cp requirements.yml sources/requirements.yml
  cp requirements.txt sources/requirements.txt
  cp README.md sources/README.md

  echo
  echo "Running 'podman build' with the following parameters:"
  echo
  echo "ansible-ver: $ansiblever"
  echo "no-cache: $nocache"
  echo

  if [[ $ansiblever == "2.5" ]]; then
    buildargs="--build-arg ANSIBLE_VER=2.5 --build-arg OS_VER=9 --build-arg RHIS_VER=$version"
  else
    buildargs="--build-arg ANSIBLE_VER=2.4 --build-arg OS_VER=9 --build-arg RHIS_VER=$version"
  fi

  if [[ $nocache == "true" ]]; then
    buildargs+=" --no-cache"
  fi

  podman build $buildargs --squash -t rhis-base-9-$ansiblever:$version .
  podman tag localhost/rhis-base-9-$ansiblever:$version rhis-base-9-$ansiblever:latest

  if [[ -n "$push_registry" && -n "$push_registry_login" && -n "$push_registry_token" ]]; then
    podman login -u=$push_registry_login -p=$push_registry_token $push_registry
    podman tag localhost/rhis-base-9-$ansiblever:$version $push_registry/$push_registry_repo/rhis-base-9-$ansiblever:$version
    podman tag localhost/rhis-base-9-$ansiblever:$version $push_registry/$push_registry_repo/rhis-base-9-$ansiblever:latest
    podman push $push_registry/$push_registry_repo/rhis-base-9-$ansiblever:$version
    podman push $push_registry/$push_registry_repo/rhis-base-9-$ansiblever:latest
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


increment_version() {
  current_version=$(get_base_version)
  
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
  echo $version > $(get_base_version_file)
}

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
