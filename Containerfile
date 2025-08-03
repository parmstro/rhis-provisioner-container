FROM registry.redhat.io/ubi9:latest
LABEL maintainer="Paul Armstrong <github:@parmstro>"
ENTRYPOINT ["/bin/bash", "-c", "echo '##########################################\nWelcome to the RHIS Provisioner container!' && exec /bin/bash"]
# rpm requirements
ARG ANSIBLE_VER
RUN dnf -y install ansible-core git vim python3 python3-ipalib python3-jmespath python3-pip bind-utils iputils bash-completion tmux
# python requirements
RUN python3 -m pip install fqdn
RUN python3 -m pip install gssapi
RUN python3 -m pip install ipalib
# ansible collection requirements
RUN mkdir -p /etc/ansible
COPY sources/ansible.cfg /etc/ansible/ansible.cfg
RUN ansible-galaxy collection install ansible.utils

RUN if [[ $ANSIBLE_VER == "2.5" ]]; then \
    echo "Installing ansible.controller collection for AAP 2.5"; \
    ansible-galaxy collection install ansible.controller:">=4.6"; \
    else \
    echo "Installing ansible.controller collection for AAP 2.4"; \
    ansible-galaxy collection install ansible.controller:"<4.6"; \
    fi

RUN ansible-galaxy collection install ansible.netcommon
RUN ansible-galaxy collection install ansible.posix
RUN ansible-galaxy collection install azure.azcollection
RUN ansible-galaxy collection install community.general
RUN ansible-galaxy collection install community.vmware
RUN ansible-galaxy collection install community.aws
RUN ansible-galaxy collection install containers.podman
RUN ansible-galaxy collection install redhat.rhel_idm
RUN ansible-galaxy collection install redhat.rhel_system_roles
RUN ansible-galaxy collection install redhat.satellite
RUN ansible-galaxy collection install redhat.satellite_operations
# add the rhis builder repos
RUN mkdir -p /rhis
WORKDIR /rhis
RUN git clone https://github.com/parmstro/rhis-builder-idm.git
RUN git clone https://github.com/parmstro/rhis-builder-satellite.git
RUN git clone https://github.com/parmstro/rhis-builder-pipelines.git
RUN git clone https://github.com/parmstro/rhis-builder-aap.git
RUN git clone https://github.com/parmstro/rhis-builder-nbde.git
RUN git clone https://github.com/parmstro/rhis-builder-day-2-ops.git
RUN git clone https://github.com/parmstro/rhis-builder-ansible-ee.git
RUN git clone https://github.com/parmstro/rhis-builder-imagebuilder.git
RUN git clone https://github.com/parmstro/rhis-builder-yubi.git
RUN git clone https://github.com/parmstro/rhis-builder-convert2rhel.git
RUN git clone https://github.com/parmstro/rhis-builder-inventory.git

# Now make the folders for group_vars, host_vars and inventory files
RUN mkdir -p /rhis/vars/external_inventory
RUN mkdir -p /rhis/vars/external_tasks
RUN mkdir -p /rhis/vars/files
RUN mkdir -p /rhis/vars/group_vars
RUN mkdir -p /rhis/vars/host_vars
RUN mkdir -p /rhis/vars/vars
RUN mkdir -p /rhis/vars/vault

# This cleans up the repo vars folders and links each project to our volume directories
# we probably need to manage this for templates and files that we want to modify as well
COPY add_softlinks.yml /rhis/add_softlinks.yml
RUN chmod +x /rhis/add_softlinks.yml
RUN ansible-playbook add_softlinks.yml

# copy the reference information
COPY podman_commands.txt /rhis/podman_commands.txt
COPY rhis-builder_sample_commands.txt /rhis/rhis-builder_sample_commands.txt
COPY README.md /rhis/README.md

# copy the sample build scripts
COPY build_idm_primary.sh /rhis/build_idm_primary.sh
RUN chmod +x /rhis/build_idm_primary.sh

COPY build_sat_primary_connected.sh /rhis/build_sat_primary_connected.sh
RUN chmod +x /rhis/build_sat_primary_connected.sh

COPY build_test_hosts.sh /rhis/build_test_hosts.sh
RUN chmod +x /rhis/build_test_hosts.sh

COPY destroy_test_hosts.sh /rhis/destroy_test_hosts.sh
RUN chmod +x /rhis/destroy_test_hosts.sh

COPY build_aap_controller24.sh /rhis/build_aap_controller24.sh
RUN chmod +x /rhis/build_aap_controller24.sh

COPY build_aap_controller24.sh /rhis/build_aap_hub24.sh
RUN chmod +x /rhis/build_aap_hub24.sh

# Cleanup the ansible configuration
COPY ansible.cfg.clean /etc/ansible/ansible.cfg
