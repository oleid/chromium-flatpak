How to build
------------

It is assumed you've followed the setup guide from https://flatpak.org/setup/

For a one time build, do the following,
```
flatpak-builder --install-deps-from=flathub --force-clean  --repo repo app org.chromium.Chromium.yml

```

go out to the park and do nice things. It will take hours to build.

If you intend to do development stuff with the package, add the `--ccache` option and increase ccache size by issuing the following command in the same folder (another terminal tab?):

```
CCACHE_DIR=.flatpak-builder/ccache/ ccache --max-size=30G
```

One full build needs about 25G, so more is better.

Credits
-------

Credits go to the brave Chromium packager of ArchLinux. Build instructions are taken from their official package.
