WEBMIN_FW_TCP_INCOMING = 22 80 443 12321

# The postinst of trixie's crowdsec registers the machine with CrowdSec's
# central API when /etc/crowdsec/online_api_credentials.yaml is missing or
# empty, and fails when it cannot: the build chroot has no DNS, and an
# identity made there would be every machine's (tracker#47). A file that is
# not empty is the package's own way to skip the registration. It is put in
# before the packages are installed and deleted by conf.d/main with the
# rest of CrowdSec's identity; keel registers the machine at the first
# enable of the crowdsec overlay. The first line of the hook is empty, as
# common's hooks require.
define root.build/pre

	mkdir -p $O/root.build/etc/crowdsec
	echo '# keel-core image build: no CAPI registration (tracker#47)' \
		> $O/root.build/etc/crowdsec/online_api_credentials.yaml
endef

include $(FAB_PATH)/common/mk/turnkey.mk
