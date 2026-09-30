#!/bin/bash

# default to AAP 2.5
ansiblever="2.5"
osver="9"
# Inuit word for packed snow used for building :-)
build="aniyu"
version_file="./version.9.25.txt"
version_mode="revision"
base_version_file="../rhis-base/version.9.25.txt" 
rhis_schema_version_file="rhis-schema-version.txt"

branch="main"
tag="latest"
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

usage() {
            echo "Usage: rhis_build_provisioner.sh [options]"
            echo "Options:"
            echo "    --no-cache - rebuild container from scratch"
            echo "    --ansible-ver - NO LONGER SUPPORTED. All builds are for AAP API 2.5 or greater."
            echo "    --os-ver - specify the OS version - one of '9' (default), or '10'"
            echo "    --branch - git branch to clone for all rhis-builder repos (default: main)"
            echo "               individual repos can be pinned via 'version:' in configure_rhis_builder.yml"
            echo "    --devel - tag the image as :devel instead of :latest; skips registry push (local only)"
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
}

# Check for no arguments, -h, or invalid options
# if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]]; then
#     usage
# fi

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -a|--ansible-ver)
            echo "    --ansible-ver - NO LONGER SUPPORTED. All builds are for AAP API 2.5 or greater."
            exit 1
            ;;
        -o|--os-ver)
            osver="$2"
            shift
            ;;
        -b|--branch)
            branch="$2"
            shift
            ;;
        -d|--devel)
            tag="devel"
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
        -h|--help)
            echo "Unknown option: $1" >&2; usage ;;

        *)
            echo "Unknown option: $1" >&2; usage ;;
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

  echo "Clean sources directory"
  mkdir -p sources
  rm -f sources/*

  echo "Configure sources"
  cp add_softlinks.yml sources/add_softlinks.yml
  cp $ansiblecfg sources/ansible.cfg
  cp ansible.cfg.clean sources/ansible.cfg.clean
  cp build_idm_primary.sh sources/build_idm_primary.sh
  cp build_idm_replicas.sh sources/build_idm_replicas.sh
  cp build_kvm_hosts.sh sources/build_kvm_hosts.sh
  cp build_quadlets.sh sources/build_quadlets.sh
  cp build_sat_1_capsules_satellite_pre.sh sources/build_sat_1_capsules_satellite_pre.sh
  cp build_sat_2_capsules.sh sources/build_sat_2_capsules.sh
  cp build_sat_3_capsules_satellite_post.sh sources/build_sat_3_capsules_satellite_post.sh
  cp build_sat_primary.sh sources/build_sat_primary.sh
  cp build_sat_disconnected_import.sh sources/build_sat_disconnected_import.sh
  cp build_sat_disconnected_export.sh sources/build_sat_disconnected_export.sh

  cp configure_aap_controller.sh sources/configure_aap_controller.sh
  
  cp deploy_idm_replica_hosts.sh sources/deploy_idm_replica_hosts.sh
  cp deploy_kvm_hypervisors.sh sources/deploy_kvm_hypervisors.sh
  cp deploy_quadlet_hosts.sh sources/deploy_quadlet_hosts.sh
  cp deploy_rhel8_test_hosts.sh sources/deploy_rhel8_test_hosts.sh
  cp deploy_rhel9_test_hosts.sh sources/deploy_rhel9_test_hosts.sh
  cp deploy_rhel10_test_hosts.sh sources/deploy_rhel10_test_hosts.sh
  cp deploy_sat_capsule_hosts.sh sources/deploy_sat_capsule_hosts.sh

  cp run_satellite_role.sh sources/run_satellite_role.sh
  cp run_idm_role.sh sources/run_idm_role.sh
  cp run_aap_role.sh sources/run_aap_role.sh

  cp configure_rhis_builder.yml sources/configure_rhis_builder.yml
  cp README.md sources/README.md
  # cp ipareplica_test_patch.py sources/ipareplica_test_patch.py
  
  cp deploy_aap_hosts.sh sources/deploy_aap_hosts.sh
  cp build_aap_controller.sh sources/build_aap_controller.sh
  cp build_aap_standalone_hub.sh sources/build_aap_standalone_hub.sh
  
  echo
  echo "Running 'podman build' with the following parameters:"
  echo
  echo "build: $build"
  echo "ansible-ver: $ansiblever"
  echo "no-cache: $nocache"
  echo

  buildargs="--build-arg ANSIBLE_VER=2.5 --build-arg OS_VER=$osver --build-arg RHIS_BASE_VER=$base_version --build-arg RHIS_VER=$version --build-arg RHIS_SCHEMA_VER=$schema_version --build-arg RHIS_BUILD=$build --build-arg PULL_PATH=$pull_path --build-arg BRANCH=$branch"
  
  if [[ $nocache == "true" ]]; then
    buildargs+=" --no-cache"
  fi

  echo $buildargs

  podman build $buildargs -t rhis-provisioner-$osver-$ansiblever:$version .
  podman tag localhost/rhis-provisioner-$osver-$ansiblever:$version rhis-provisioner-$osver-$ansiblever:$tag

  if [[ $tag == "devel" ]]; then
    echo "Devel build — skipping registry push. Image tagged locally as rhis-provisioner-$osver-$ansiblever:devel"
  elif [[ $push_registry && $push_registry_login && $push_registry_token ]]; then
    podman login -u=$push_registry_login -p=$push_registry_token $push_registry
    podman tag localhost/rhis-provisioner-$osver-$ansiblever:$version $push_registry/$push_registry_repo/rhis-provisioner-$osver-$ansiblever:$version
    podman tag localhost/rhis-provisioner-$osver-$ansiblever:$version $push_registry/$push_registry_repo/rhis-provisioner-$osver-$ansiblever:$tag
    podman push $push_registry/$push_registry_repo/rhis-provisioner-$osver-$ansiblever:$version
    podman push $push_registry/$push_registry_repo/rhis-provisioner-$osver-$ansiblever:$tag
  fi

  echo "Clean sources directory"
  rm -f sources/*
}

get_base_version() {
  base_version_file="../rhis-base/version.$osver.25.txt" 
  current_base_version=$(cat $base_version_file)
  echo "${current_base_version}"
}

get_base_version_file() {
  base_version_file="../rhis-base/version.$osver.25.txt" 
  echo "${base_version_file}"
}

get_rhis_version() {
  rhis_version_file="./version.$osver.25.txt" 
  current_version=$(cat $rhis_version_file)
  echo "${current_version}"
}

get_rhis_version_file() {
  rhis_version_file="./version.$osver.25.txt" 
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

if [[ $ansiblever != "2.5" ]]; then
  echo "ERROR: Invalid ansible version. ONLY AAP API 2.5 builds are supported for the container."
  exit 1
fi

if [[ $osver != "9" && $osver != "10" ]]; then
  echo "ERROR: Invalid operating system version. Only RHEL '9' or '10' builds are supported for the container."
  exit 2
fi

base_version=$(get_base_version)
version=$(increment_version "$version_mode")
build=$(cat ../build.txt)

# Run main commands
build_container

# Check the exit status of the main commands
if [[ $? -eq 0 ]]; then
    # If build was successful, increment the revision
    echo "Successfully built $version for operating system $osver - Updating version file."
    update_version
else
    echo "One or more build commands failed. Version file not updated."
fi
