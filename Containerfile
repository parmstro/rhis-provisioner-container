FROM registry.redhat.io/ubi9:latest
LABEL maintainer="Paul Armstrong <github:@parmstro>"
# rpm requirements
RUN dnf -y install ansible-core git vim python3 python3-ipalib python3-jmespath python3-pip bind-utils
# python requirements
RUN python3 -m pip install fqdn
RUN python3 -m pip install gssapi
RUN python3 -m pip install ipalib
# ansible collection requirements
RUN mkdir -p /etc/ansible
COPY sources/ansible.cfg /etc/ansible/ansible.cfg
RUN ansible-galaxy collection install ansible.controller:"<4.6"
RUN ansible-galaxy collection install ansible.netcommon
RUN ansible-galaxy collection install ansible.posix
RUN ansible-galaxy collection install ansible.utils
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
# Now make the folders for group_vars, host_vars and inventory files

# Override the copy the softlink creation script to the container.

# Cleanup the ansible configuration
COPY sources/ansible.cfg.clean /etc/ansible/ansible.cfg
