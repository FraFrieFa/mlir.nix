{
  description = "Custom-Built MLIR Tools";

  # Nixpkgs / NixOS version to use.
  #inputs.nixpkgs.url = "nixpkgs/nixos-23.11";
  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let

      # git revision to use (for version and git pull
      #llvmRevision = "llvmorg-17-init";
      llvmRevision = "08ed557714eed7f5cde9d1c5606f58280683884a";
      circtRevision = "39b4f01a665e62b8770ea66b31abe7c1b8a9bfb2";

      # to work with older version of flakes
      lastModifiedDate = self.lastModifiedDate or self.lastModified or "19700101";

      # Generate a user-friendly version number.
      #version = builtins.substring 0 8 lastModifiedDate;
      version = circtRevision;

      # System types to support.
      supportedSystems = [ "x86_64-linux" ]; #"x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlays.default ]; });

    in

    {

      # A Nixpkgs overlay.
      overlays.default = final: prev: {

        mlir = with final; llvmPackages_17.stdenv.mkDerivation rec {
          name = "mlir-${version}";

          src = fetchFromGitHub {
            owner = "llvm";
            repo = "llvm-project";
            rev = llvmRevision;
            sha256 = "sha256-9fNCqUDWI3Rjizkps5vgLy0ZtMgFeFmyh1yCWLj8NVc="; # lib.fakeSha256;
          };

          sourceRoot = "source/llvm";

          nativeBuildInputs = [
            python3
            ninja
            cmake
            ncurses
            zlib
            llvmPackages_17.llvm
            llvmPackages_17.clang
            llvmPackages_17.bintools
          ];

          buildInputs = [ libxml2 ];


          cmakeFlags = [
            "-GNinja"
            # Debug for debug builds
            "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
            # from the original LLVM expr
            "-DLLVM_LINK_LLVM_DYLIB=ON"
            #"-DBUILD_SHARED_LIBS=ON"
            # inst will be our installation prefix
            #"-DCMAKE_INSTALL_PREFIX=../inst"
            # "-DLLVM_INSTALL_TOOLCHAIN_ONLY=ON"
            # install tools like FileCheck
            "-DLLVM_INSTALL_UTILS=ON"
            # change this to enable the projects you need
            "-DLLVM_ENABLE_PROJECTS=mlir"
            # "-DLLVM_BUILD_EXAMPLES=ON"
            # this makes llvm only to produce code for the current platform, this saves CPU time, change it to what you need
            "-DLLVM_TARGETS_TO_BUILD=X86"
#            -DLLVM_TARGETS_TO_BUILD="X86;NVPTX;AMDGPU" \
            # NOTE(feliix42): THIS IS ABI BREAKING!!
            "-DLLVM_ENABLE_ASSERTIONS=ON"
            # Using clang and lld speeds up the build, we recomment adding:
            "-DCMAKE_C_COMPILER=clang"
            "-DCMAKE_CXX_COMPILER=clang++"
            "-DLLVM_ENABLE_LLD=ON"
            #"-DLLVM_USE_LINKER=${llvmPackages_17.bintools}/bin/lld"
            # CCache can drastically speed up further rebuilds, try adding:
            #"-DLLVM_CCACHE_BUILD=ON"
            # libxml2 needs to be disabled because the LLVM build system ignores its .la
            # file and doesn't link zlib as well.
            # https://github.com/ClangBuiltLinux/tc-build/issues/150#issuecomment-845418812
            #"-DLLVM_ENABLE_LIBXML2=OFF"
          ];

          # TODO(feliix42): Fix this, as it requires the python package `lit`
          # postInstall = ''
          #   cp bin/llvm-lit $out/bin
          # '';
        };

        circt = with final; llvmPackages_17.stdenv.mkDerivation rec {
          name = "circt-${version}";

          src = fetchFromGitHub {
            owner = "llvm";
            repo = "circt";
            rev = circtRevision;
            sha256 = "sha256-/4UrcwVyQnOwJMpRn0tMfJi/zm5rmrnv9IBE7/2rOY8="; # lib.fakeSha256;
          };

          sourceRoot = "source/";

          nativeBuildInputs = [
            python3
            ninja
            cmake
            #ncurses
            #zlib
            #llvmPackages_17.llvm
            llvmPackages_17.clang
            llvmPackages_17.bintools
            mlir
            lit
          ];

          #buildInputs = [ libxml2 ];


          cmakeFlags = [
            "-GNinja"
            "-DMLIR_DIR=${mlir}/lib/cmake/mlir"
            "-DLLVM_DIR=${mlir}/lib/cmake/llvm"

            # Debug for debug builds
            "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
            # from the original LLVM expr
            "-DLLVM_LINK_LLVM_DYLIB=ON"
            # this makes llvm only to produce code for the current platform, this saves CPU time, change it to what you need
            "-DLLVM_TARGETS_TO_BUILD=X86"
            # NOTE(feliix42): THIS IS ABI BREAKING!!
            "-DLLVM_ENABLE_ASSERTIONS=ON"
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
            # Using clang and lld speeds up the build, we recomment adding:
            "-DCMAKE_C_COMPILER=clang"
            "-DCMAKE_CXX_COMPILER=clang++"
            "-DLLVM_ENABLE_LLD=ON"
            "-DLLVM_EXTERNAL_LIT=${lit}/bin/lit"
          ];

          # TODO(feliix42): Fix this, as it requires the python package `lit`
          # postInstall = ''
          #   cp bin/llvm-lit $out/bin
          # '';
        };

      };

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) mlir;
          inherit (nixpkgsFor.${system}) circt;
        });

      hydraJobs = {
        mlir."x86_64-linux" = self.packages."x86_64-linux".mlir;
        circt."x86_64-linux" = self.packages."x86_64-linux".circt;
      };

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      # defaultPackage = forAllSystems (system: self.packages.${system}.mlir self.packages.${system}.circt);

      # A NixOS module, if applicable (e.g. if the package provides a system service).
      nixosModules.mlir =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [ self.overlays.default ];

          environment.systemPackages = [ pkgs.mlir ];

          #systemd.services = { ... };
        };

      nixosModules.circt =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [ self.overlays.default ];

          environment.systemPackages = [ pkgs.circt ];

          #systemd.services = { ... };
        };

    };
}

