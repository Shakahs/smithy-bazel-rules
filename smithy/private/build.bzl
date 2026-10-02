"""smithy_build: the output of one `smithy build` plugin, such as a code generator."""

load("@rules_java//java/common:java_info.bzl", "JavaInfo")
load(":cli.bzl", "CLI_ATTRS", "MODEL_ATTRS", "model_jars", "run_smithy")

_SCRIPT = """
output="$PWD/$1"; projection="$2"; plugin="$3"; shift 3
build="$(mktemp -d)"
smithy build --quiet --output "$build" --projection "$projection" --plugin "$plugin" "$@"
cp -R "$build/$projection/$plugin/." "$output"
"""

def _smithy_build_impl(ctx):
    output = ctx.actions.declare_directory(ctx.label.name)
    dependencies = model_jars(ctx.attr.deps)

    args = ctx.actions.args()
    args.add(output.path)
    args.add(ctx.attr.projection)
    args.add(ctx.attr.plugin)
    args.add("--config", ctx.file.config)
    args.add_joined("--discover-classpath", dependencies, join_with = ctx.configuration.host_path_separator)
    args.add_all(ctx.files.srcs)

    run_smithy(
        ctx,
        script = _SCRIPT,
        script_args = args,
        outputs = [output],
        inputs = depset(ctx.files.srcs + [ctx.file.config], transitive = [dependencies]),
        plugins = ctx.attr.plugins,
        mnemonic = "SmithyBuild",
        progress_message = "Running Smithy plugin {} of projection {} for %{{label}}".format(
            ctx.attr.plugin,
            ctx.attr.projection,
        ),
    )

    return [DefaultInfo(files = depset([output]))]

smithy_build = rule(
    implementation = _smithy_build_impl,
    doc = """Runs one plugin of one projection of a smithy-build.json, as a directory.

The directory holds what the plugin wrote, the projection's
`<projection>/<plugin>` folder of a `smithy build` output tree.""",
    attrs = MODEL_ATTRS | CLI_ATTRS | {
        # A projection may build a published model alone, which its deps carry.
        "srcs": attr.label_list(
            allow_files = [".smithy", ".json"],
            doc = "The model's IDL or JSON AST files, beside the models its deps carry.",
        ),
        "config": attr.label(
            allow_single_file = [".json"],
            mandatory = True,
            doc = "The smithy-build.json that configures the projection and its plugin.",
        ),
        "projection": attr.string(
            mandatory = True,
            doc = "The projection to build.",
        ),
        "plugin": attr.string(
            mandatory = True,
            doc = "The plugin of that projection whose output this is.",
        ),
        "plugins": attr.label_list(
            providers = [JavaInfo],
            cfg = "exec",
            doc = "Build plugins the CLI loads, such as //smithy/plugins:rust_client_codegen.",
        ),
    },
)
