# rhis-provisioner Container build

WAIT. Unless you are developing for rhis-builder, just download the current containers and get started!

For building RHIS with AAP 2.4:

podman pull quay.io/parmstro/rhis-provision-9-2.4:latest

For building RHIS with AAP 2.5:

podman pull quay.io/parmstro/rhis-provision-9-2.5:latest

NEXT.

The rhis-provisioner container simplifies getting started with the Red Hat Infrastructure Standard and rhis-builder. 
The container is designed to have all the projects, dependencies and examples for building a Red Hat Infrastructure Standard environment.
The rhis-provisioner container provides the interactive provisioner environment for building an infrastructure based on the RH-ISAM.
When launched, the container mounts your configuration and provides a command line access to the ansible playbooks that are used to build the infrastructure and manage it day 2 (see the example.ca.24.sh script in the inventory project below). 
All you need is git and podman on your system and then pull the container. 

Then go get the sample configuration from [rhis-builder-inventory](https://github.com/parmstro/rhis-builder-inventory)

If you want to contribute to the container or extend it for your own projects, read on.

### Building the containers.

If you are here, you care about developing and extending rhis-builder bits.

The rhis-proivsioner container build is separated into two parts. 

We always build a base image using ubi9:latest and add the ansible collections and related dependencies. This is the rhis-base container. There is a version for AAP 2.4 and AAP 2.5 as these different AAP versions have non-compatible ansible collections. This can take some time and the collections change much slower than some of the advances in RHIS, so avoiding building this every time speeds your development process.

We then build the rhis-provisioner container. Again a AAP 2.4 version and AAP 2.5 version from the respective base. This is a quick build that adds all the rhis-builder repos into the container and sets the environment to read either the example.ca sample from rhis-builder-inventory or your customized version of it. This current container build script defaults to include dependencies for AAP 2.4. If you require the container to build for AAP 2.5, pass the appropriate arg to the rhis_build_base.sh  and rhis_build_provisioner scripts.

For customization of the configuration, clone the rhis-builder-inventory project and then copy the contents to a new directory and then push it to a private git repo of your choice. You can then (relatively) safely store your configuration in a confidential fashion. Follow all the recommendations about vaulting secrets and avoid pushing confidential content to any git repo.

**NOTE**: There is a simple way to extend the container by including your own playbooks in the external_tasks directory under the rhis-builder-inventory when you launch your container!

The rhis-provisioner container is designed to provide the interactive provisioner environment for building an infrastructure base on the RH-ISAM.

The container build process is managed by the rhis_build_base.sh and rhis_build_provisioner.sh bash script. Ensure the scripts are executable by the current user and then run the scripts. This will create a localhost copy of both containers. The rhis-provisioner build by default pulls from localhost/rhis-base-9-$aapver:latest

~~~
rhis_build_base.sh
rhis_build_provisioner.sh
~~~

Pass --no-cache to the rhis_build.sh script to force the build script to regenerate all content.

~~~
./rhis_build_base.sh --no-cache
./rhis_build_provisioner.sh --no-cache
~~~

By default, the above results in a rhis-provisioner container that is compatible with building and managing an RHIS environment utilizing Ansible Automation Platform 2.4. The container created will be **rhis-provisioner-9-2.4:latest**

To build the container to build and manage an RHIS enviroment that utilizes AAP 2.5. pass "--ansible-ver 2.5" to the build script. The container created will be **rhis-provisioner-9-2.5:latest**

~~~
./rhis_build_base.sh --no-cache --ansible-ver 2.5
./rhis_build_provisioner.sh --no-cache --ansible-ver 2.5
~~~

Now if you are looking to publish a copy to your external registry, you can do something like:

~~~
./rhis_build_base.sh --no-cache --ansible-ver 2.5 --push_registry="quay.example.ca" --push_repo "my_rhis"
./rhis_build_provisioner.sh --no-cache --ansible-ver 2.5 --push_registry="quay.example.ca" --push_repo "my_rhis"
~~~

You can also specify pull registries 

Once the container is built, you can launch the container directly or use the script.
Using the run_container.sh to launch the container is strongly recommended as it coordinates mounting your vault, group_vars, host_vars, and inventory directories for your custom build into the container and securing the files. 

### Running the run_container.sh script.

The run_container.sh script controls launching the container. The script takes several parameters that represent the paths to the various directory that you store your ansible vault files and your custom configuration. With these parameters the script launches ***rhis-provisioner-9-2.4:latest*** which is suitable for building an RHIS environment that utilizes Ansible Automation Platform 2.4. To launch the container ***rhis-provisioner-9.2.5:latest*** pass **'--ansible-ver 2.5'** to the run_container.sh script. The script allows for the providing individual paths to each of the allowable ansible configuration directories so that you have complete flexibility for merging configurations across your builds. (We have configured the launch this way to allow for the greatest flexibility in both development and delivery configuration).

* **--secrets-dir**   
    * REQUIRED. 
    * This is the path in the executing users home directory that stores the vault files that you will use, in particular, rhis_builder_vault.yml
* **--external-tasks-dir**
    * This is the path in the executing users home directory that stores the external_tasks directory for rhis-builder repositories
    * External task are additional tasks that users run to prepare or extend their RHIS environment from within the rhis-provisioner container
* **--files-dir**
    * This is the path in the executing users home directory that stores the files directory for rhis-builder repositories. 
    * As an example this is where the OpenSCAP contents and tailoring files are located
* **--group-vars-dir**
    * This is the path in the executing users home directory that stores the group_vars directory for rhis-builder repositories
    * e.g. /home/ansiblerunner/rhis/rhis-builder-inventory/example.ca/vault
* **--host-vars-dir**
    * This is the path in the executing users home directory that stores the host_vars directory for rhis-builder repositories
    * e.g. /home/ansiblerunner/rhis/rhis-builder-inventory/example.ca/group_vars
* **--inventory-dir**
    * This is the path in the executing users home directory that stores an inventory directory that contains your inventory file
    * e.g. /home/ansiblerunner/rhis/rhis-builder-inventory/example.ca/inventory
* **--templates-dir**
    * This is the path in the executing users home directory that stores the templates directory for rhis-builder repositories
    * As an example, all the job, partitioning and provisioning templates for the rhis-builder repositories are stored here.
* **--vars-dir**
    * This is the path in the executing users home directory that stores the vars directory for rhis-builder repositories
    * As an example, any non-secret variable files that need to be made available to the rhis-builder repositories are stored here.
* **--ansible-ver 2.5**
    * This launches the container rhis-provisioner-9-2.5:latest with the above parameters to provide a provisioner to build AAP 2.5.
    * Omitting the parameter or specifying '2.4' for the version will launch the environment for AAP 2.4

For example, if you used rhis-builder-provisioner to prepare your provisioner node, you should have the rhis-builder-inventory project cloned to your provisioner node. Running the following command will launch the container and connect it to the projects inventory directories:

~~~

# runs an environment capable of building RHIS with AAP 2.4
./run_container.sh --secrets-dir ~/rhis/rhis-builder-inventory/example.ca/vault \
                   --external-tasks-dir ~/rhis/rhis-builder-inventory/example.ca/external_tasks \
                   --files-dir ~/rhis/rhis-builder-inventory/example.ca/files \
                   --group-vars-dir ~/rhis/rhis-builder-inventory/example.ca/group_vars \
                   --host-vars-dir ~/rhis/rhis-builder-inventory/example.ca/host_vars \
                   --inventory-dir ~/rhis/rhis-builder-inventory/example.ca/inventory \
                   --templates-dir ~/rhis/rhis-builder-inventory/example.ca/templates \
                   --vars-dir ~/rhis/rhis-builder-inventory/example.ca/vars

# runs an environment capable of building RHIS with AAP 2.5 (i.e. includes ansible.controller >= version 4.6)
./run_container.sh --secrets-dir ~/rhis/rhis-builder-inventory/example.ca/vault \
                   --external-tasks-dir ~/rhis/rhis-builder-inventory/example.ca/external_tasks \
                   --files-dir ~/rhis/rhis-builder-inventory/example.ca/files \
                   --group-vars-dir ~/rhis/rhis-builder-inventory/example.ca/group_vars \
                   --host-vars-dir ~/rhis/rhis-builder-inventory/example.ca/host_vars \
                   --inventory-dir ~/rhis/rhis-builder-inventory/example.ca/inventory \
                   --templates-dir ~/rhis/rhis-builder-inventory/example.ca/templates \
                   --vars-dir ~/rhis/rhis-builder-inventory/example.ca/templates \
                   --ansible-ver 2.5

## NOTE: Your configuration files must include the appropriate 
## references to synchronize and load the appropriate 2.5 content!
~~~
The example.ca.24.sh and example.ca.25.sh in the inventory porject are setup to run this for run_container.sh for you with similar parameters to the above. See the inventory project.

Once you are comfortable navigating the projects, you can build your own configurations and launch the script with all the parameters.
This is where you will build your own RHIS environment.
There is a series of samples that explain when you will use each of the playbooks that are provided.

### Running an RHIS builder projects plays.

In general in all projects, there are 4 playbooks.

- main.yml - is the primary entry point for a project and will run all the configured roles and tasks in order to build the complete project components.

The other 3 playbooks are utility plays that are useful for testing and debugging configurations, day 2 operations, configuration remediation, etc..

- run_role.yml - the play that takes the name of the role as an extra variable (e.g. -e "role_name=activation_keys"), loads your variable files and executes only that role.
- run_role_task.yml - most roles in RHIS consist of multiple tasks. This playbook allows you to dig in where necessary and run a particular task.
- run_task.yml - in several of the rhis-builder projects, there are tasks that are outside the bounds of a particular role. This playbook accepts the task

See the rhis-builder_sample_commands.txt for running various roles, tasks or full builds with your own custom configuration instead of the example.ca demo environment.

Please, comments, feature requests, issues, and pull requests are all welcome.

Regards,

The RHIS Team

