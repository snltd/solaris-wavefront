# Solaris Wavefront

A collection of stuff made to help you use
[Wavefront](http://wavefront.com) with Solaris and Illumos.

## `build_wf_proxy.sh`

A script which pulls a release of the Wavefront proxy from Github,
and builds it locally. The build process is a bit of a moving target
at the time of writing (August 2016) and the script may or may not
work with the latest build. I'll try to keep it up-to-date, but I
can't promise.

## SMF

This directory contains an SMF method and manifest, which works with
the proxy produced by `build_wf_proxy.sh`.
