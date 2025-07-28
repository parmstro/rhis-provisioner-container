rhis-provisioner Container build

This project simplifies getting started with the Red Hat Infrastructure Standard and rhis-builder.
The container is designed to have all the projects, dependencies and examples for building a Red Hat Infrastructure Standard environment.
This current container build is designed to include dependencies for AAP 2.4. There will be a container that implements ansible.controller collection version 4.6+ to support AAP 2.5.
The container is designed to provide the interactive provisioner environment.
You can build the container from the Containerfile using the rhis_build.sh script.
You can pass --no-cache to the rhis_build.sh script to force the build to generate a fresh build.

Use run_container.sh to launch the container.

See the podman_commands.txt for running with your own custom configuration instead of the example.ca demo environment.

See the rhis-builder_sample_commands.txt for running various roles, tasks or full builds with your own custom configuration instead of the example.ca demo environment.

