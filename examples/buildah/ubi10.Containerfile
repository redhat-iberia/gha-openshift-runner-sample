FROM registry.access.redhat.com/ubi10:10.0

# Don't include container-selinux and remove
# directories used by yum that are just taking
# up space.
RUN useradd build; dnf -y update; dnf -y reinstall shadow-utils; dnf -y install buildah fuse-overlayfs /usr/share/containers/storage.conf; rm -rf /var/cache/* /var/log/dnf* /var/log/yum.*

# Adjust storage.conf to enable Fuse storage.
RUN sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' /usr/share/containers/storage.conf
RUN mkdir -p /var/lib/shared/overlay-images /var/lib/shared/overlay-layers; touch /var/lib/shared/overlay-images/images.lock; touch /var/lib/shared/overlay-layers/layers.lock

# Set up environment variables to note that this is
# not starting with usernamespace and default to
# isolate the filesystem with chroot.
ENV _BUILDAH_STARTED_IN_USERNS="" BUILDAH_ISOLATION=chroot