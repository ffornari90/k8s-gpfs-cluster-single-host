FROM redhat/ubi8
ENV DEPENDENCIES="yes"
COPY ./assets/repos/centos-8-baseos.repo /etc/yum.repos.d/
COPY ./assets/repos/centos-8-appstream.repo /etc/yum.repos.d/
RUN yum install -y http://ds-004.cr.cnaf.infn.it:8080/kernel-rpms/kernel-headers-4.18.0-305.49.1.el8_4.x86_64.rpm && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    yum install -y http://ds-004.cr.cnaf.infn.it:8080/kernel-rpms/kernel-devel-4.18.0-305.49.1.el8_4.x86_64.rpm && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    yum install -y python3 python3-devel python3-pip git \
    perl initscripts iproute hostname \
    make cpp gcc gcc-c++ elfutils-devel elfutils \
    openssh-server glibc-locale-source glibc-all-langpacks && \
    yum clean all && \
    rm -rf /var/cache/yum
RUN pip3 install CherryPy && \
    git clone https://github.com/gdraheim/docker-systemctl-replacement.git && \
    cp docker-systemctl-replacement/files/docker/systemctl3.py /usr/bin/ && \
    cp docker-systemctl-replacement/files/docker/systemctl3.py /bin/systemctl && \
    cp docker-systemctl-replacement/files/docker/journalctl3.py /bin/journalctl
CMD /usr/sbin/sshd -D
