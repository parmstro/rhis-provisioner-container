### rhis-base-container

This folder contains the container build information for the rhis-base-container. It builds the base container for rhis-provisioner-container project by installing the required binaries, python modules and ansible collections. The base container changes infrequently when there are updates to these underlying requirements or the ubi9:latest container. By separating the base container from the provisioner container we reduce rhis-provisioner-container build times for development and allow ourselves to move faster.

We have decided to build our base container from scratch using ubi9:latest as the public ansible execution environment container does not maintain the collections at the speed that we require for our project. This would result in us having to update these collections anyway. It is cleaner and results in fewer layers if we build this ourselves. As we solidify our inclusions, we will optimize the layers for the base container. 

The goal is to have this container built automatically and pushed to quay.io when necessary. The rhis-provisioner-container build will pull from quay.io as necessary when the underlying container is updated.

Just like the original container build, we will have an ansible 2.4 and ansible 2.5 build of the base container due to collection requirements.

As always, your contributions to the project are essential, PRs are welcome. 

Thanks!

The RHIS Team.
