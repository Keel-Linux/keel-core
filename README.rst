Keel Linux Core
===============

This is the core appliance of `Keel Linux`_: the base system every other
Keel appliance is layered on, compatible with TurnKey Linux appliances. It
is a fork of `turnkeylinux-apps/core`_ with its full history; upstream is
kept as the remote ``upstream`` and this repository tracks its ``master``.
The recipe (``Makefile``, ``plan/main``, ``conf.d``, ``overlay``) builds the
same image as upstream, as checked by the M0 gate of the project, and the
project's own changes are kept small and reviewable on top of it.

Upstream declares no license for this recipe. The project's own
contributions to this repository are licensed GPL-3.0-or-later (``LICENSE``;
project decision 0007); upstream content keeps whatever terms upstream gives
it. Test state and plan: ``COVERAGE.md``. The organization guidelines that
every Keel repository follows are at
https://keel-linux.github.io/guidelines.html.

.. _Keel Linux: https://github.com/keel-linux
.. _turnkeylinux-apps/core: https://github.com/turnkeylinux-apps/core

The upstream description follows.

TurnKey Core - Debian GNU/Linux with Batteries Included
=======================================================

TurnKey Core is the base operating system which all TurnKey GNU/Linux
solutions share in common. It is commonly deployed standalone as a
convenient starting point for custom system integrations. Benefits
include automatic daily security updates, 1-click backup and restore (TKLBAM),
a web control panel (Webmin), and preconfigured system monitoring (Monit) with
optional email alerts.

Features:

- **Base Operating System**: Debian GNU/Linux 'stable'.

- **Build formats**: Deploys on bare metal, virtual machines (e.g.,
  OpenStack, VMWare, VirtualBox, LXC, KVM, Xen) and in the cloud.
   
  - `ISO images`_: Generic installable Live CD. Installs anywhere.
  - `Virtual Machine images`_: Optimized for virtualized hardware,
    pre-installed and ready to run.
  - Amazon Machine Image (AMI): Best launched via the `TurnKey
    Hub`_.

- **Free as in speech**: `free software`_ with `full source code`_ and a
  `powerful build system`_. Free of hidden backdoors, free from
  restrictive licensing and free to learn from, modify and distribute.

- **Secure and easy to maintain**: `Auto-updated daily`_ with latest
  Debian security patches. Optional monitoring and email notification of
  `system alerts`_.

- **1-click backup and restore** (`TKLBAM`_): smart backup and data
  migration software saves changes to files, databases and package
  management to encrypted storage which a system can be automatically
  restored from.
  
- **Dynamic DNS** (`HubDNS`_): Associates your IP with a custom domain
  or the free \*.tklapp.com domain.

- **Logical Volume Management** (`LVM`_): Instead of installing to a
  fixed size partition, a Logical Volume is first created by default,
  and this may later be expanded, even across multiple physical devices.

- **Web management interface (WebUI)** (`Webmin`_):
   
  - Listens on port 12321 (uses SSL).
  - Provides fully interactive shell in your web browser.
  - Modern responsive theme: 'Authentic'.
  - Network modules:
     
    - Firewall configuration (with example configuration).
    - Network configuration.

  -  System modules:
     
     - Backup and migration (TKLBAM).
     - Configure time, date and timezone.
     - Configure users and groups.
     - Manage software packages.
     - Change passwords.
     - System logs.

  -  Tool modules:
     
     - Fully interactive shell.
     - Text editor.
     - Simple file upload/download.
     - File manager (HTML5).
     - Custom commands.

  -  Hardware modules:
     
     - Partitions on local disks.
     - Logical volume management.

- **Simple configuration console (cli)** (`confconsole`_):
   
  - Displays basic usage information.
  - Configure networking.
  - Let's Encrypt SSL/TLS certificates.
  - Mail SMTP relay setup.
  - Proxy settings.
  - Region and timezone.
  - Other global system settings.

- **First boot initialization** (`inithooks`_):
   
  - Prompt user for passwords.
  - Regenerates SSL and SSH cryptographic keys.
  - Installs latest security updates, unless user chooses to defer this
    for later.

- **Command line power tools**
   
  - Smart, programmable bash shell completion: helps you get more done
    with fewer keystrokes.
  - Support for $HOME/.bashrc.d `shell hooks`_
  - Persistent environment variables (see $HOME/.bashrc.d/penv)::

       penv-set pydoc /usr/share/doc/python2.7/html
       exit
       # later...
       cd $pydoc

- **Automatic time synchronization with NTP**

- Take a look at some `screenshots`_.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH: username **root**

.. _free software: https://www.turnkeylinux.org/license
.. _full source code: https://github.com/turnkeylinux-apps
.. _powerful build system: https://www.turnkeylinux.org/tkldev
.. _system alerts: https://www.turnkeylinux.org/docs/automatic-security-alerts
.. _screenshots: https://www.turnkeylinux.org/screenshots/148
.. _headless build types: https://www.turnkeylinux.org/docs/builds#builds-table
.. _ISO images: https://www.turnkeylinux.org/docs/builds#iso
.. _Virtual Machine images: https://www.turnkeylinux.org/docs/builds#vm
.. _TurnKey Hub: https://hub.turnkeylinux.org
.. _AMI codes: https://www.turnkeylinux.org/docs/ec2/ami
.. _TKLBAM: https://www.turnkeylinux.org/tklbam
.. _Auto-updated daily: https://www.turnkeylinux.org/docs/automatic-security-updates
.. _HubDNS: https://www.turnkeylinux.org/dns
.. _LVM: https://tldp.org/HOWTO/LVM-HOWTO/
.. _confconsole: https://www.turnkeylinux.org/docs/confconsole#main-screen-and-basic-functionality
.. _Webmin: https://webmin.com/
.. _inithooks: https://github.com/turnkeylinux/inithooks
.. _shell hooks: https://www.turnkeylinux.org/blog/generic-shell-hooks
