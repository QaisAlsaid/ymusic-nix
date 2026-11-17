{
  lib,
  stdenv,
  fetchurl,
  copyDesktopItems,
  makeDesktopItem,
  patchelf,
  glib,
  libGL,
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
    libsecret
    libxkbcommon
    mesa
    pulseaudio
    wayland
    zlib
    libxcb
    stdenv.cc.cc
  ];

  # The bundled libav libraries have libz.so.1 in their NEEDED
  # (libavcodec, libavformat, libavutil, libswscale), and the bundled
  # ffmpeg binary does too. Normal distros provide zlib from the host;
  # NixOS does not. DT_RUNPATH is NOT transitive, so every bundled lib
  # must carry these dirs in its own rpath - YMusic's rpath cannot
  # satisfy them.
  bundledRpath = lib.makeLibraryPath [
    zlib
    stdenv.cc.cc
  ];
in
stdenv.mkDerivation {
  pname = "ymusic";
  inherit version;

  src = fetchurl (
    release.sources.${stdenv.hostPlatform.system}
      or (throw "YMusic has no AppImage for ${stdenv.hostPlatform.system}")
  );

  nativeBuildInputs = [
    copyDesktopItems
    patchelf
  ];

  buildInputs = [
    glib
    libGL
    libsecret
    libxkbcommon
    mesa
    pulseaudio
    wayland
    zlib
    stdenv.cc.cc
    libxcb
  ];

  # No build from source needed: the official AppImage ships the app,
  # a self-contained ffmpeg build and all libav libs. Its type-2 runtime
  # has a built-in --appimage-extract mode that needs no FUSE.
  unpackPhase = ''
    runHook preUnpack
    cp $src ./ymusic.AppImage
    chmod +x ./ymusic.AppImage
    ./ymusic.AppImage --appimage-extract >/dev/null
    mv squashfs-root ymusic
    chmod -R u+w ymusic
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/opt/ymusic
    cp -r ymusic/. $out/opt/ymusic/

    mkdir -p $out/bin
    ln -s $out/opt/ymusic/usr/bin/YMusic $out/bin/ymusic

    install -Dm644 ymusic/io.ymusic.YMusic.png \
      $out/share/pixmaps/ymusic.png
    runHook postInstall
  '';

  # The AppImage normally relies on the host loader at /lib64/ and on
  # LD_LIBRARY_PATH set by its runtime; on NixOS both must be replaced:
  #  - point the interpreter at the Nix glibc loader
  #  - make the bundled libav libs and the dlopen()ed system libs
  #    resolvable through absolute RUNPATHs
  preFixup = ''
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
