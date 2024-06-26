"""Provider that serves as an API for adding any files needed for apko build"""

_PATH_CONVENTION_DOC = """
 When referencing other files in the config yaml file use paths relative to your Bazel workspace root. 
    For example, if you want to reference source file foo/bar/baz use foo/bar/baz. If you want to reference output file of foo/bar:rule and rule's 
    output file is rule.out, reference it as foo/bar/rule.out.
"""

ApkoConfigInfo = provider(
    doc = """Information about apko config. May be used when generating apko config file instead of using hardcoded ones.
    {}
    """.format(_PATH_CONVENTION_DOC),
    fields = {
        "files": "depset of files that will be needed for building. All of them will be added to the execution of apko commands when built with Bazel.",
    },
)

def _apko_config_impl(ctx):
    config = ctx.file.config
    out = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.symlink(
        target_file = config,
        output = out,
    )

    apko_depsets = []
    for dep in ctx.attr.deps:
        if ApkoConfigInfo in dep:
            apko_depsets.append(dep[ApkoConfigInfo].files)
    direct_deps = [out]
    for dep in ctx.files.deps:
        direct_deps.append(dep)

    return [
        DefaultInfo(
            files = depset([out]),
        ),
        ApkoConfigInfo(
            files = depset(direct_deps, transitive = apko_depsets),
        ),
    ]

apko_config = rule(
    implementation = _apko_config_impl,
    attrs = {
        "deps": attr.label_list(
            allow_empty = True,
            default = [],
            allow_files = True,
            doc = """
            List of all dependencies of the config. Transitive dependencies are included based on 
            ApkoConfigInfo provider.
            """,
        ),
        "config": attr.label(
            allow_single_file = True,
            doc = """
        Config of the image. Either in source directory or generated by Bazel.
        {}
        """.format(_PATH_CONVENTION_DOC),
        ),
    },
)
