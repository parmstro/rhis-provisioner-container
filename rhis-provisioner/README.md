### rhis-provisioner-container

This folder contains the container build information for the rhis-provisioner-container. It builds the provisioner container from the base container by adding the individual rhis projects into the container image and setting it up to consume the inventory. The base container changes infrequently when there are updates to the underlying ubi9 container, binaries, collections and python modules. By separating the base container from the provisioner container we reduce container build times for development and allow ourselves to move faster as the collection deployment is very time consuming. We only will rebuild this container when we have committed changes in the upstream rhis repos. 

The goal is to eventually get on a schedule for releases for this container to ensure stability and repeatable infrastructure builds. 

See the [README.md](../rhis-base-container/README.md) in the rhis-base-container folder for details.


If you have suggestions, requests or have found a bug, please open an issue against this project. This will allow us to centrally manage the issues for the underlying projects for visibility and allow us to involve the proper team for the underlying project. We will pull together an issue template soon to help with ensure we have the required debugging information. 

Just like the original container build, we will have an AAP 2.4 and an AAP 2.5+ build of the rhis-provisioner-container due to collection requirement differences for AAP 2.4 and AAP 2.5 and greater.

As always, your contributions to the project are essential, PRs are welcome. 

Thanks!

The RHIS Team.