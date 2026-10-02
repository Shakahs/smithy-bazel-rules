"""smithy_library: a validated Smithy model packaged as a discoverable jar."""

load("@rules_java//java/common:java_common.bzl", "java_common")
load("@rules_java//java/common:java_info.bzl", "JavaInfo")
load(":cli.bzl", "CLI_ATTRS", "MODEL_ATTRS", "SmithyModelInfo", "model_jars", "run_smithy")

# The source projection's `sources` plugin writes the model files and the manifest that
# lists them, which is what a model jar carries under META-INF/smithy. Entries are added
# in sorted order with a fixed timestamp, so the jar's bytes depend on its content alone.
_SCRIPT = """
jar_tool="$PWD/$1"; output="$PWD/$2"; shift 2
build="$(mktemp -d)"
smithy build --quiet --output "$build" --projection source --plugin sources "$@"
stage="$(mktemp -d)"
mkdir "$stage/META-INF"
mv "$build/source/sources" "$stage/META-INF/smithy"
cd "$stage"
find META-INF -type f | LC_ALL=C sort > "$build/entries"
"$jar_tool" --create --no-manifest --date=1980-01-01T00:00:02Z --file "$output" "@$build/entries"
"""

def _smithy_library_impl(ctx):
    jar = ctx.actions.declare_file(ctx.label.name + ".jar")
    java_runtime = ctx.attr._java_runtime[java_common.JavaRuntimeInfo]
    dependencies = model_jars(ctx.attr.deps)

    args = ctx.actions.args()
    args.add(java_runtime.java_home + "/bin/jar")
    args.add(jar)
    args.add_joined("--discover-classpath", dependencies, join_with = ctx.configuration.host_path_separator)
    args.add_all(ctx.files.srcs)

    run_smithy(
        ctx,
        script = _SCRIPT,
        script_args = args,
        outputs = [jar],
        inputs = depset(ctx.files.srcs, transitive = [dependencies]),
        mnemonic = "SmithyLibrary",
        progress_message = "Validating and packaging the Smithy model %{label}",
    )

    return [
        DefaultInfo(files = depset([jar])),
        SmithyModelInfo(jars = depset([jar], transitive = [dependencies])),
        JavaInfo(
            output_jar = jar,
            compile_jar = jar,
            deps = [dep[JavaInfo] for dep in ctx.attr.deps if JavaInfo in dep],
        ),
    ]

smithy_library = rule(
    implementation = _smithy_library_impl,
    doc = """Validates a Smithy model and packages it as a jar with a META-INF/smithy manifest.

The jar is a model dependency of other Smithy rules, and, through its JavaInfo, of any
tool that discovers models on a classpath (such as a code generator taking model jars).
Source files are packaged by file name, so two sources may not share one.""",
    attrs = MODEL_ATTRS | CLI_ATTRS,
    provides = [SmithyModelInfo, JavaInfo],
)
