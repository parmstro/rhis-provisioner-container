rhis-provisioner Container build

This project simplifies getting started with the Red Hat Infrastructure Standard and rhis-builder.
The container is designed to have all the projects, dependencies and examples for building a Red Hat Infrastructure Standard environment.
This current container build is designed to include dependencies for AAP 2.4. There will be a container that implements ansible.controller collection version 4.6+ to support AAP 2.5.
The container is designed to provide the interactive provisioner environment.
You can build the container from the Containerfile using the rhis_build.sh script.
Pass --no-cache to the rhis_build.sh script to force the build script to regenerate all content.

Once the container is built, you can launch the container directly or use the script.
Using the run_container.sh to launch the container is strongly recommended as it coordinates mounting your vault, group_vars, host_vars, and inventory directories for your custom build into the container and securing the files. 

### Running the run_container.sh script.

The run_container.sh script requires one parameter, the path to directory that you store your ansible vault files in for rhis-builder projects.
It also takes 3 additional parameters necessary to build your custom environment.

--secrets-dir:    this is the path in the executing users home directory that stores the vault files that you will use, in particular, rhis_builder_vault.yml
--group-vars-dir: this is the path in the executing users home directory that stores the group_vars directory for rhis-builder projects
--host-vars-dir:  this is the path in the executing users home directory that stores the host_vars directory for rhis-builder projects
--inventory-dir:  this is the path in the executing users home directory that stores an inventory directory that contains your inventory file

Running the script with only the --secrets-dir parameter will allow you to make use of the example.ca sample configurations inside the container to create a demo environment and to learn about the project.

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

