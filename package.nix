{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  copyDesktopItems,
  makeDesktopItem,
  makeWrapper,
  patchelf,
  glib,
  libGL,
  libffi,
  libsecret,
  libxkbcommon,
  mesa,
  pulseaudio,
  wayland,
  zlib,
  libxcb,
}:

let
  release = import ./version.nix;
  inherit (release) version;

  # System libs the YMusic binary links against or dlopen()s at runtime
  # (X11/XWayland via xcb, Wayland, EGL, PulseAudio audio output,
  # libsecret credential storage backed by glib).
  ymusicRpath = lib.makeLibraryPath [
    glib
    libGL
    libffi
    libsecret
    libxkbcommon
    mesa
    pulseaudio
    wayland
    zlib
    libxcb
    stdenv.cc.cc
    stdenv.cc.libc
  ];

  # The bundled libav libraries have libz.so.1 in their NEEDED
  # (libavcodec, libavformat, libavutil, libswscale), and the bundled
  # ffmpeg binary does too. Normal distros provide zlib from the host;
  # NixOS does not. DT_RUNPATH is NOT transitive, so every bundled lib
  # must carry these dirs in its own rpath - YMusic's rpath cannot
  # satisfy them. libc/libm are carried the same way nixpkgs binaries
  # carry glibc in their own RUNPATH.
  bundledRpath = lib.makeLibraryPath [
    zlib
    stdenv.cc.cc
    stdenv.cc.libc
  ];

  appimage = fetchurl (
    release.sources.${stdenv.hostPlatform.system}
      or (throw "YMusic has no AppImage for ${stdenv.hostPlatform.system}")
  );

  # Extract the AppImage WITHOUT executing it. The type-2 runtime refuses
  # to start inside the Nix build sandbox (execve fails there), so running
  # `--appimage-extract` is not an option. appimageTools.extract locates
  # the embedded squashfs image from the ELF header offset and unpacks it
  # with unsquashfs instead - exactly what nixpkgs' appimage packaging
  # uses. The result is the plain AppDir: usr/bin/YMusic, usr/bin/ffmpeg,
  # usr/lib/libav*.so, the desktop file and icons.
  appdir = appimageTools.extract {
    pname = "ymusic";
    inherit version;
    src = appimage;
  };
in
stdenv.mkDerivation {
  pname = "ymusic";
  inherit version;

  src = appdir;

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
    patchelf
  ];

  buildInputs = [
    glib
    libGL
    libffi
    libsecret
    libxkbcommon
    mesa
    pulseaudio
    wayland
    zlib
    stdenv.cc.cc
    libxcb
  ];

  # No build from source needed: the official AppImage ships the app, a
  # self-contained ffmpeg build and all libav libs, and appimageTools
  # (via src) already unpacked it. Just copy the AppDir in and make the
  # tree writable.
  unpackPhase = ''
    runHook preUnpack
    cp -r $src ymusic
    chmod -R u+w ymusic
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/opt/ymusic
    cp -r ymusic/. $out/opt/ymusic/

    mkdir -p $out/bin
    # gpui (the UI framework) dlopen()s Wayland (and EGL) libraries at
    # runtime; dlopen'ed libraries are invisible to RUNPATH-based link
    # resolution, and the wayland package's unversioned .so symlinks live
    # in its dev output. LD_LIBRARY_PATH is consulted first for every
    # dlopen, whatever the nixpkgs snapshot's output layout is.
    makeWrapper $out/opt/ymusic/usr/bin/YMusic $out/bin/ymusic \
      --prefix LD_LIBRARY_PATH : "$out/opt/ymusic/usr/lib:$ymusicRpath:$bundledRpath:${lib.getDev wayland}/lib"

    install -Dm644 ymusic/io.ymusic.YMusic.png \
      $out/share/pixmaps/ymusic.png
    runHook postInstall
  '';

  # The AppImage normally relies on the host loader at /lib64/ and on
  # LD_LIBRARY_PATH set by its runtime; on NixOS both must be replaced.
  # This runs in postFixup ON PURPOSE: stdenv's fixupPhase ends with
  # `patchelf --shrink-rpath`, which prunes every RUNPATH entry that no
  # DT_NEEDED library resolves from. That is correct for linked libraries,
  # but it deletes the directories only dlopen() (Wayland, EGL/GL, glib,
  # PulseAudio, libsecret) ever resolves from - which is exactly what
  # surfaced at runtime as "The wayland library could not be loaded".
  # postFixup runs after the shrink, so these RUNPATHs stay intact.
  postFixup = ''
    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      $out/opt/ymusic/usr/bin/YMusic \
      $out/opt/ymusic/usr/bin/ffmpeg

    patchelf --set-rpath "$out/opt/ymusic/usr/lib:${ymusicRpath}" \
      $out/opt/ymusic/usr/bin/YMusic

    patchelf --set-rpath "$out/opt/ymusic/usr/lib:${bundledRpath}" \
      $out/opt/ymusic/usr/bin/ffmpeg

    for f in $out/opt/ymusic/usr/lib/*.so.*; do
      patchelf --set-rpath "$out/opt/ymusic/usr/lib:${bundledRpath}" "$f"
    done
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "ymusic";
      desktopName = "YMusic";
      exec = "ymusic %U";
      icon = "ymusic";
      comment = "Music player";
      categories = [
        "AudioVideo"
        "Audio"
        "Player"
      ];
      mimeTypes = [
        "audio/mpeg"
        "audio/mp4"
        "audio/x-m4a"
        "audio/x-m4b"
        "audio/aac"
        "audio/flac"
        "audio/x-flac"
        "audio/wav"
        "audio/x-wav"
        "audio/ogg"
        "audio/opus"
        "audio/webm"
        "audio/x-matroska"
        "video/mp4"
        "video/x-m4v"
        "video/quicktime"
        "video/webm"
        "video/x-matroska"
        "x-scheme-handler/ymusic"
      ];
      startupWMClass = "io.ymusic.YMusic";
      singleMainWindow = true;
    })
  ];

  meta = with lib; {
    description = "Multiplatform music player that plays YouTube as audio only";
    longDescription = ''
      YMusic streams just the audio track of YouTube music videos, saving
      data and CPU. Features include background playback, SponsorBlock
      integration, a sleep timer, a ten-band equalizer, offline saving and
      a local music library. This package repacks the official Linux
      AppImage release instead of building from source.
    '';
    homepage = "https://ymusic.io/";
    license = licenses.gpl3Only;
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
    mainProgram = "ymusic";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
