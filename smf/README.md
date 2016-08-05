# Wavefront SMF

This directory contains a method and manifest to run a Wavefront
proxy on a Solaris 11 or SmartOS host.

A Wavefront user is required, created with something like this:

```
# useradd -u 104 -g 12 -s /bin/false -c 'Wavefront Proxy' -d /var/tmp wavefront
```

or via your preferred config management software.

The manifest assumes the method is at
`/usr/local/lib/svc/manifest/wavefront-proxy`,
and the method assumes the proxy is installed under
`/opt/wavefront/proxy-x.y`. It will use the highest `x.y` version
number it finds.

Logs will be written to `/var/log/wavefront`, so make that writeable
by your `wavefront` user.

The service is called `wavefront/proxy`.
