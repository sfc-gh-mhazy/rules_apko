"""Declare runtime dependencies

These are needed for local dev, and users must install them as well.
See https://docs.bazel.build/versions/main/skylark/deploying.html#dependencies
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//apko/private:toolchains_repo.bzl", "PLATFORMS", "toolchains_repo")
load("//apko/private:versions.bzl", "APKO_VERSIONS")

LATEST_APKO_VERSION = APKO_VERSIONS.keys()[0]

def http_archive(name, **kwargs):
    maybe(_http_archive, name = name, **kwargs)

# WARNING: any changes in this function may be BREAKING CHANGES for users
# because we'll fetch a dependency which may be different from one that
# they were previously fetching later in their WORKSPACE setup, and now
# ours took precedence. Such breakages are challenging for users, so any
# changes in this function should be marked as BREAKING in the commit message
# and released only in semver majors.
# This is all fixed by bzlmod, so we just tolerate it for now.
def rules_apko_dependencies():
    # The minimal version of bazel_skylib we require
    http_archive(
        name = "bazel_skylib",
        sha256 = "74d544d96f4a5bb630d465ca8bbcfe231e3594e5aae57e1edbf17a6eb3ca2506",
        urls = [
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
        ],
    )

    http_archive(
        name = "aspect_bazel_lib",
        sha256 = "09b51a9957adc56c905a2c980d6eb06f04beb1d85c665b467f659871403cf423",
        strip_prefix = "bazel-lib-1.34.5",
        url = "https://github.com/aspect-build/bazel-lib/releases/download/v1.34.5/bazel-lib-v1.34.5.tar.gz",
    )

########
# Remaining content of the file is only used to support toolchains.
########
_DOC = "Fetch external tools needed for apko toolchain"
_ATTRS = {
    "apko_version": attr.string(mandatory = True),
    "platform": attr.string(mandatory = True),
    "sha256": attr.string(mandatory = True),
    "url": attr.string(mandatory = True),
    "strip_prefix": attr.string(mandatory = False, default = ""),
}

def _apko_repo_impl(repository_ctx):
    repository_ctx.download_and_extract(
        integrity = repository_ctx.attr.sha256,
        stripPrefix = repository_ctx.attr.strip_prefix,
        url = repository_ctx.attr.url,
    )
    repository_ctx.file(
        "BUILD.bazel",
        """\
# Generated by apko/repositories.bzl
load("@rules_apko//apko:toolchain.bzl", "apko_toolchain")
apko_toolchain(
    name = "apko_toolchain", 
    # After https://github.com/chainguard-dev/apko/issues/827 is fixed,
    # this may need to be conditional so it's "apko.exe" on Windows.
    apko = "apko",
    version = "{version}",
)
""".format(version = repository_ctx.attr.apko_version),
    )

apko_repositories = repository_rule(
    _apko_repo_impl,
    doc = _DOC,
    attrs = _ATTRS,
)

def apko_binary_spec(url, sha256, version, strip_prefix):
    return struct(url = url, sha256 = sha256, version = version, strip_prefix = strip_prefix)

def _build_platform_to_apko_binary_map(apko_version):
    version = apko_version.lstrip("v")
    result = {}
    for platform in PLATFORMS.keys():
        url = "https://github.com/chainguard-dev/apko/releases/download/v{version}/apko_{version}_{platform}.tar.gz".format(
            version = version,
            platform = platform,
        )
        sha256 = APKO_VERSIONS[apko_version][platform]
        strip_prefix = "apko_{}_{}".format(
            version,
            platform,
        )
        result[platform] = apko_binary_spec(
            url = url,
            sha256 = sha256,
            version = version,
            strip_prefix = strip_prefix,
        )
    return result

# Wrapper macro around everything above, this is the primary API
def apko_register_toolchains(name, apko_version = LATEST_APKO_VERSION, platform_to_apko_binary_map = None, register = True):
    """Convenience macro for users which does typical setup.

    - create a repository for each built-in platform like "apko_linux_amd64" -
      this repository is lazily fetched when node is needed for that platform.
    - create a repository exposing toolchains for each platform like "apko_platforms"
    - register a toolchain pointing at each platform
    Users can avoid this macro and do these steps themselves, if they want more control.
    Args:
        name: base name for all created repos, like "apko1_14"
        register: whether to call through to native.register_toolchains.
            Should be True for WORKSPACE users, but false when used under bzlmod extension
        apko_version: version of apko
        platform_to_apko_binary_map: specialized way of providing urls of apko binaries for the toolchains.
            If specified, apko_version is ignored. It is a dict of platform string to struct produced by
            apko_binary_spec macro that consists of url to the archive with apko binary, it's sha256, version
            of apko and prefix that should be stripped after unpacking the archive. The prefix
            should specified, so that apko binary lands in top level directory after stripping.
            The intention here is to allow using apko versions that are not included in versions.bzl.
    """
    map = platform_to_apko_binary_map
    if map == None:
        map = _build_platform_to_apko_binary_map(apko_version)
    for platform, apko_spec in map.items():
        if platform not in PLATFORMS.keys():
            fail("Unsupported platform: {}".format(platform))
        apko_repositories(
            name = name + "_" + platform,
            platform = platform,
            sha256 = apko_spec.sha256,
            url = apko_spec.url,
            apko_version = apko_spec.version,
            strip_prefix = apko_spec.strip_prefix,
        )
        if register:
            native.register_toolchains("@%s_toolchains//:%s_toolchain" % (name, platform))

    toolchains_repo(
        name = name + "_toolchains",
        user_repository_name = name,
        platforms = map.keys(),
    )
