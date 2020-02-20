# This is a striped down version of the ArchLinux package, taken from
# https://git.archlinux.org/svntogit/packages.git/tree/trunk/PKGBUILD?h=packages/chromium
# 
# Original ArchLinux credits:
# Maintainer: Evangelos Foutras <evangelos@foutrelis.com>
# Contributor: Pierre Schmitz <pierre@archlinux.de>
# Contributor: Jan "heftig" Steffens <jan.steffens@gmail.com>
# Contributor: Daniel J Griffiths <ghost1227@archlinux.us>

pkgname=chromium
pkgver=80.0.3987.116
pkgrel=1
_launcher_ver=6

# Possible replacements are listed in build/linux/unbundle/replace_gn_files.py
# Keys are the names in the above script; values are the dependencies in Arch
declare -gA _system_libs=(
  [ffmpeg]=ffmpeg
  [flac]=flac
  [fontconfig]=fontconfig
  [freetype]=freetype2
  [harfbuzz-ng]=harfbuzz
  [icu]=icu
  [libdrm]=
  [libjpeg]=libjpeg
  #[libpng]=libpng    # https://crbug.com/752403#c10
  #[libvpx]=libvpx    # compile error, maybe too old?
  [libwebp]=libwebp
  [libxml]=libxml2
  [libxslt]=libxslt
  [opus]=opus
  #[re2]=re2          # not available in Platform
  #[snappy]=snappy    # dito
  #[yasm]=            # dito
  #[zlib]=minizip     # dito
)
_unwanted_bundled_libs=(
  ${!_system_libs[@]}
  ${_system_libs[libjpeg]+libjpeg_turbo}
)
depends+=(${_system_libs[@]})

# Google API keys (see https://www.chromium.org/developers/how-tos/api-keys)
# Note: These are for Arch Linux use ONLY. For your own distribution, please
# get your own set of keys.
_google_api_key=AIzaSyDwr302FpOSkGRpLlUpPThNTDPbXcIn_FM
_google_default_client_id=413772536636.apps.googleusercontent.com
_google_default_client_secret=0ZChLK6AxeA3Isu96MkwqDR4

prepare() {
  # Allow building against system libraries in official builds
  sed -i 's/OFFICIAL_BUILD/GOOGLE_CHROME_BUILD/' \
    tools/generate_shim_headers/generate_shim_headers.py

  # https://crbug.com/893950
  sed -i -e 's/\<xmlMalloc\>/malloc/' -e 's/\<xmlFree\>/free/' \
    third_party/blink/renderer/core/xml/*.cc \
    third_party/blink/renderer/core/xml/parser/xml_document_parser.cc \
    third_party/libxml/chromium/*.cc

  mkdir -p third_party/node/linux/node-linux-x64/bin
  ln -s $(pwd)/bin/node third_party/node/linux/node-linux-x64/bin/

  # Remove bundled libraries for which we will use the system copies; this
  # *should* do what the remove_bundled_libraries.py script does, with the
  # added benefit of not having to list all the remaining libraries
  local _lib
  for _lib in ${_unwanted_bundled_libs[@]}; do
    find "third_party/$_lib" -type f \
      \! -path "third_party/$_lib/chromium/*" \
      \! -path "third_party/$_lib/google/*" \
      \! -path 'third_party/yasm/run_yasm.py' \
      \! -regex '.*\.\(gn\|gni\|isolate\)' \
      -delete
  done

  python3 build/linux/unbundle/replace_gn_files.py \
    --system-libraries "${!_system_libs[@]}"
}

build() {
  # Avoid falling back to preprocessor mode when sources contain time macros
  export CCACHE_SLOPPINESS=time_macros

  echo "*********************************************************************"
  if [ "$(ccache --get-config=disable)" = "true" ] ; then
    echo "Not using ccache for build. Makes sense for an oneshot run."
    export CC="clang"
    export CXX="clang++"
  else
    echo "Using ccache for build, please use at least 25G of cache, otherwise"
    echo "it gets overwritten before you're done."
    echo "Cache size is: $(ccache --get-config=max_size)"
    export CC="ccache clang"
    export CXX="ccache clang++"
  fi
  echo "*********************************************************************"

  # needed for proper thin-lto-linking
  export AR=llvm-ar
  export NM=nm

  # for java and some python2 scripts
  export PATH=$PATH:/usr/lib/sdk/openjdk/bin:$(pwd)/bin
  ln -s /app/bin/python2 bin/python

  local _flags=(
    'custom_toolchain="//build/toolchain/linux/unbundle:default"'
    'host_toolchain="//build/toolchain/linux/unbundle:default"'
    'clang_use_chrome_plugins=false'
    'is_official_build=true' # implies is_cfi=true on x86_64
    'treat_warnings_as_errors=false'
    'fieldtrial_testing_like_official_build=true'
    'ffmpeg_branding="Chrome"'
    'proprietary_codecs=true'
    'rtc_use_pipewire=true'
    'link_pulseaudio=true'
    'use_gnome_keyring=false'
    'use_sysroot=false'
    'linux_use_bundled_binutils=false'
    'use_custom_libcxx=false'
    'enable_hangout_services_extension=true'
    'enable_widevine=true'
    'enable_nacl=false'
    'enable_swiftshader=false'
    "google_api_key=\"${_google_api_key}\""
    "google_default_client_id=\"${_google_default_client_id}\""
    "google_default_client_secret=\"${_google_default_client_secret}\""
  )

  if [[ -n ${_system_libs[icu]+set} ]]; then
    _flags+=('icu_use_data_file=false')
  fi

  #if check_option strip y; then
    _flags+=('symbol_level=0')
  #fi

  # Facilitate deterministic builds (taken from build/config/compiler/BUILD.gn)
  CFLAGS+='   -Wno-builtin-macro-redefined'
  CXXFLAGS+=' -Wno-builtin-macro-redefined'
  CPPFLAGS+=' -D__DATE__=  -D__TIME__=  -D__TIMESTAMP__='

  # Do not warn about unknown warning options
  CFLAGS+='   -Wno-unknown-warning-option'
  CXXFLAGS+=' -Wno-unknown-warning-option'

  ./gn gen out/Release --args="${_flags[*]}" --script-executable=/app/bin/python2
  ninja -C out/Release chrome chrome_sandbox chromedriver || exit 1
}

package() {
  install -D out/Release/chrome "$FLATPAK_DEST/lib/chromium/chromium"
  install -Dm4755 out/Release/chrome_sandbox "$FLATPAK_DEST/lib/chromium/chrome-sandbox"
  ln -s /app/lib/chromium/chromedriver "$FLATPAK_DEST/bin/chromedriver"

  install -Dm644 chrome/installer/linux/common/desktop.template \
    "$FLATPAK_DEST/share/applications/org.chromium.Chromium.desktop"
  install -Dm644 chrome/app/resources/manpage.1.in \
    "$FLATPAK_DEST/share/man/man1/chromium.1"
  sed -i \
    -e "s/@@MENUNAME@@/Chromium Flatpak/g" \
    -e "s/@@PACKAGE@@/org.chromium.Chromium/g" \
    -e "s:/usr/bin/@@USR_BIN_SYMLINK_NAME@@:/app/bin/chromium:g" \
    "$FLATPAK_DEST/share/applications/org.chromium.Chromium.desktop" \
    "$FLATPAK_DEST/share/man/man1/chromium.1"

  cp \
    out/Release/{chrome_{100,200}_percent,resources}.pak \
    out/Release/{*.bin,chromedriver} \
    "$FLATPAK_DEST/lib/chromium/"
  install -Dm644 -t "$FLATPAK_DEST/lib/chromium/locales" out/Release/locales/*.pak

  if [[ -z ${_system_libs[icu]+set} ]]; then
    cp out/Release/icudtl.dat "$FLATPAK_DEST/lib/chromium/"
  fi

  for size in 24 48 64 128 256; do
    install -Dm644 "chrome/app/theme/chromium/product_logo_$size.png" \
      "$FLATPAK_DEST/share/icons/hicolor/${size}x${size}/apps/org.chromium.Chromium.png"
  done

  for size in 16 32; do
    install -Dm644 "chrome/app/theme/default_100_percent/chromium/product_logo_$size.png" \
      "$FLATPAK_DEST/share/icons/hicolor/${size}x${size}/apps/org.chromium.Chromium.png"
  done

  install -Dm644 LICENSE "$FLATPAK_DEST/share/licenses/chromium/LICENSE"
}

prepare
build
package
# vim:set ts=2 sw=2 et:
