#!/bin/bash

ansiblever="2.5"
osver="9"
version_file="./version.$osver.25.txt"
version_mode="revision"

nocache="true"
do_scan="true"
buildargs=""
ansiblecfg="/etc/ansible/ansible.cfg"
push_registry="quay.io"
push_registry_repo="parmstro"
push_registry_login=""
push_registry_token=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -a|--ansible-ver)
            echo "--ansible-ver - no longer supported. ONLY AAP API 2.5 builds are supported for the container."
            exit 1
            ;;
        -o|--os-ver)
            osver="$2"
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
        -s|--scan)
            do_scan="true"
            ;;
        --no-scan)
            do_scan="false"
            ;;
        -h|--help)
            echo "Usage: rhis_build_base.sh [options]"
            echo "Options:"
            echo "    --no-cache - rebuild container from scatch"
            echo "    --ansible-ver - NO LONGER SUPPORTED. ONLY AAP API 2.5 builds are supported for the container."
            echo "    --ansible-config path_spec - provide the path specification to the ansible.cfg file (default: /etc/ansible/ansible.cfg)"
            echo "    --push-registry - the name of the remote registry to push the final image to (default: quay.io)"
            echo "    --push-registry_repo - the name of the repo in the remote registry to push the final image to (default: parmstro)"
            echo "    --push-registry-login - the login for the push registry (e.g. mybot)"
            echo "    --push-registry-token - the authentication token for the push registry"
            echo "    --version-mode - increment major, minor, or revision version of the build"
            echo "    --scan - enable security scanning (default: enabled)"
            echo "    --no-scan - skip security scanning for quick dev iterations"
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

stage_sources() {
  rm -f sources/*
  cp $ansiblecfg sources/ansible.cfg
  cp ansible.cfg.clean sources/ansible.cfg.clean
  cp requirements.$osver.yml sources/requirements.yml
  cp requirements.$osver.txt sources/requirements.txt
  cp README.md sources/README.md
}

build_container() {
  echo "Starting build of rhis-base container version: $version for AAP version: $ansiblever"
  echo
  echo "Ensuring ansible and podman requirements are installed..."
  sudo dnf -y install ansible-core podman

  echo "Using registry.redhat.io as the pull registry"
  podman login registry.redhat.io

  stage_sources

  echo
  echo "Running 'podman build' with the following parameters:"
  echo
  echo "ansible-ver: $ansiblever"
  echo "no-cache: $nocache"
  echo

  buildargs="--build-arg ANSIBLE_VER=$ansiblever --build-arg OS_VER=$osver --build-arg RHIS_VER=$version"

  if [[ $nocache == "true" ]]; then
    buildargs+=" --no-cache"
  fi

  podman build $buildargs --squash-all -t rhis-base-$osver-$ansiblever:$version .
  if [[ $? -ne 0 ]]; then
    echo "ERROR: podman build failed."
    rm -f sources/*
    return 1
  fi

  podman tag localhost/rhis-base-$osver-$ansiblever:$version rhis-base-$osver-$ansiblever:latest
  if [[ $? -ne 0 ]]; then
    echo "ERROR: podman tag failed."
    return 1
  fi

  rm -f sources/*
  return 0
}

push_container() {
  if [[ -n "$push_registry" && -n "$push_registry_login" && -n "$push_registry_token" ]]; then
    echo "Pushing to $push_registry/$push_registry_repo"
    podman login -u=$push_registry_login -p=$push_registry_token $push_registry
    podman tag localhost/rhis-base-$osver-$ansiblever:$version $push_registry/$push_registry_repo/rhis-base-$osver-$ansiblever:$version
    podman tag localhost/rhis-base-$osver-$ansiblever:$version $push_registry/$push_registry_repo/rhis-base-$osver-$ansiblever:latest
    podman push $push_registry/$push_registry_repo/rhis-base-$osver-$ansiblever:$version
    if [[ $? -ne 0 ]]; then
      echo "ERROR: podman push failed."
      return 1
    fi
    podman push $push_registry/$push_registry_repo/rhis-base-$osver-$ansiblever:latest
    return $?
  else
    echo "push_registry parameters not defined. Local build only."
    return 0
  fi
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

if [[ $ansiblever != "2.5" ]]; then
  echo "ERROR: Invalid ansible version. Only AAP API 2.5 or greater builds are supported for the container."
  exit 1
fi

if [[ $osver != "9" && $osver != "10" ]]; then
  echo "ERROR: Invalid operating system version. Only RHEL '9' or '10' builds are supported for the container."
  exit 2
fi

version=$(increment_version "$version_mode")
build=$(cat ../build.txt)
image_name="localhost/rhis-base-$osver-$ansiblever:$version"

# ── Create build reports directory ──────────────────────────────────────
build_timestamp=$(date -u +%Y%m%d-%H%M%S)
reports_dir="./scan-reports/build-ubi${osver}-${build_timestamp}"

# ── Pre-build scanning ──────────────────────────────────────────────────
if [[ "$do_scan" == "true" ]]; then
    echo "Running pre-build security scan..."
    ./scan_base.sh --phase pre-build --os-ver "$osver" --ansible-config "$ansiblecfg" --reports-dir "$reports_dir"
    if [[ $? -ne 0 ]]; then
        echo "Pre-build scan failed. Aborting build."
        exit 3
    fi
else
    echo "Scanning disabled (--no-scan). Skipping pre-build scan."
fi

# ── Build ────────────────────────────────────────────────────────────────
build_container
if [[ $? -ne 0 ]]; then
    echo "Build failed. Version file not updated."
    exit 4
fi

# ── Registry login (before post-build so push+sign can happen in pipeline) ──
registry_image=""
if [[ -n "$push_registry" && -n "$push_registry_repo" ]]; then
    registry_image="${push_registry}/${push_registry_repo}/rhis-base-${osver}-${ansiblever}:${version}"
    if [[ -n "$push_registry_login" && -n "$push_registry_token" ]]; then
        echo "Logging in to ${push_registry}..."
        podman login -u="$push_registry_login" -p="$push_registry_token" "$push_registry"
        if [[ $? -ne 0 ]]; then
            echo "ERROR: Registry login failed."
            exit 5
        fi
    fi
    podman tag "$image_name" "$registry_image"
    podman tag "$image_name" "${push_registry}/${push_registry_repo}/rhis-base-${osver}-${ansiblever}:latest"
fi

# ── Post-build scanning + push + sign ───────────────────────────────────
if [[ "$do_scan" == "true" ]]; then
    echo "Running post-build security scan..."
    scan_args=(--phase post-build --image "$image_name" --reports-dir "$reports_dir")
    if [[ -n "$registry_image" ]]; then
        scan_args+=(--registry-image "$registry_image")
    fi
    ./scan_base.sh "${scan_args[@]}"
    if [[ $? -ne 0 ]]; then
        echo "Post-build scan failed. Image built but not pushed. Version file not updated."
        exit 6
    fi
else
    echo "Scanning disabled (--no-scan). Skipping post-build scan."
    # Push without signing when scanning is disabled
    if [[ -n "$registry_image" ]]; then
        push_container
        if [[ $? -ne 0 ]]; then
            echo "Push failed. Version file not updated."
            exit 7
        fi
    fi
fi

# ── Push :latest tag ────────────────────────────────────────────────────
if [[ -n "$registry_image" ]]; then
    echo "Pushing :latest tag..."
    podman push "${push_registry}/${push_registry_repo}/rhis-base-${osver}-${ansiblever}:latest"
    if [[ $? -ne 0 ]]; then
        echo "WARNING: :latest tag push failed (versioned image already pushed)."
    fi
fi

# ── Version update only on full success ──────────────────────────────────
echo "Successfully built, scanned, and pushed $version - Updating version file."
update_version
