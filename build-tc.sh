#!/usr/bin/env bash

# Function to show an informational message
msg() {
    echo -e "\e[1;32m$*\e[0m"
}

err() {
    echo -e "\e[1;41m$*\e[0m"
}

# Set a directory
DIR="$(pwd ...)"

# Git info
G_USER=neekless
G_REL_REPO=neekless/nickel-clang
G_BUILD_REPO=neekless/tc-build

# Build Info
rel_date="$(date "+%Y%m%d")" # ISO 8601 format
rel_friendly_date="$(date "+%B %-d, %Y")" # "Month day, year" format
builder_commit="$(git rev-parse HEAD)"

# Build LLVM
msg "Building LLVM..."
./build-llvm.py \
	--clang-vendor "Nickel" \
	--defines "LLVM_PARALLEL_COMPILE_JOBS=$(nproc --all) LLVM_PARALLEL_LINK_JOBS=$(nproc --all) CMAKE_C_FLAGS=-O3 CMAKE_CXX_FLAGS=-O3" \
	--targets "ARM;AArch64;X86" \
	--shallow-clone \
	--incremental \

# Check if the final clang binary exists or not.
[ ! -f install/bin/clang-1* ] && {
	err "Building LLVM failed ! Kindly check errors !!"
	exit 1
}

# Build binutils
msg "Building binutils..."
./build-binutils.py --targets arm aarch64 x86_64

# Remove unused products
rm -fr install/include
rm -f install/lib/*.a install/lib/*.la

# Strip remaining products
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
	strip -s "${f: : -1}"
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
	# Remove last character from file output (':')
	bin="${bin: : -1}"

	echo "$bin"
	patchelf --set-rpath "$DIR/install/lib" "$bin"
done

# Release Info
pushd llvm-project || exit
llvm_commit="$(git rev-parse HEAD)"
short_llvm_commit="$(cut -c-8 <<< "$llvm_commit")"
popd || exit

llvm_commit_url="https://github.com/llvm/llvm-project/commit/$short_llvm_commit"
binutils_ver="$(ls | grep "^binutils-" | sed "s/binutils-//g")"
clang_version="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"

# Push to GitHub
# Update Git repository
git config --global user.name "$G_USER"
git config --global user.email "6415551-neekless@users.noreply.gitlab.com"
git clone "https://$G_USER:$GITLAB_TOKEN@gitlab.com/$G_REL_REPO.git" rel_repo
pushd rel_repo || exit
rm -fr ./*
cp -r ../install/* .
# Keep files that aren't part of the toolchain itself
git checkout README.md LICENSE
git add .
git commit -am "Update to $rel_date build

LLVM commit: $llvm_commit_url
Clang Version: $clang_version
Binutils version: $binutils_ver
Builder commit: https://github.com/$G_BUILD_REPO/commit/$builder_commit"

# Downgrade the HTTP version to 1.1
git config --global http.version HTTP/1.1
# Increase git buffer size
git config --global http.postBuffer 55428800

git push -f
popd || exit

# Set git buffer to original size
git config --global http.version HTTP/2
