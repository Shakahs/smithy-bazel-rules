"""Running the Smithy CLI in an action, and the model jars it reads."""

load("@rules_java//java/common:java_common.bzl", "java_common")
load("@rules_java//java/common:java_info.bzl", "JavaInfo")

SmithyModelInfo = provider(
    doc = "The model jars a Smithy model library and the libraries it builds on contribute.",
    fields = {
        "jars": "depset of jars carrying a META-INF/smithy manifest",
    },
)

MODEL_ATTRS = {
    "srcs": attr.label_list(
        allow_files = [".smithy", ".json"],
        mandatory = True,
        doc = "The model's IDL or JSON AST files.",
    ),
    "deps": attr.label_list(
        providers = [[SmithyModelInfo], [JavaInfo]],
        doc = "Model libraries the sources build on: `smithy_library` targets, or published " +
              "model jars such as a trait package. A published jar contributes only itself; its " +
              "own Java dependencies are the CLI's to provide.",
    ),
}

CLI_ATTRS = {
    "_cli": attr.label(
        default = "//smithy:cli",
        providers = [JavaInfo],
        cfg = "exec",
    ),
    "_java_runtime": attr.label(
        default = "@bazel_tools//tools/jdk:current_java_runtime",
        providers = [java_common.JavaRuntimeInfo],
        cfg = "exec",
    ),
}

_CLI_MAIN_CLASS = "software.amazon.smithy.cli.SmithyCli"

def model_jars(deps):
    """The model jars of `deps` and of the libraries they build on.

    Args:
        deps: Targets of a rule's `deps` attribute.

    Returns:
        A depset of jars.
    """
    return depset(
        [jar for dep in deps if SmithyModelInfo not in dep for jar in dep[JavaInfo].runtime_output_jars],
        transitive = [dep[SmithyModelInfo].jars for dep in deps if SmithyModelInfo in dep],
    )

# Defines `smithy`, which runs the CLI, from the launcher's two leading arguments, and
# shifts them off so the rule's script sees only its own.
_PROLOGUE = """set -euo pipefail
java="$1"; classpath="$2"; shift 2
smithy() {{ command="$1"; shift; "$java" -cp "$classpath" {main_class} "$command" --no-color "$@"; }}
""".format(main_class = _CLI_MAIN_CLASS)

def run_smithy(ctx, script, script_args, outputs, inputs, plugins = [], mnemonic = "Smithy", progress_message = None):
    """Runs `script`, which calls the Smithy CLI as `smithy <command> <arguments>`.

    Plugins run in the CLI's JVM, so their jars join its classpath. Model jars never do;
    the script passes them to the CLI as models.

    Args:
        ctx: The rule context; it must carry CLI_ATTRS.
        script: Bash script receiving `script_args` as its positional parameters.
        script_args: Args object with the script's own arguments.
        outputs: Files and directories the action writes.
        inputs: depset of the files the action reads, besides the CLI's classpath.
        plugins: JavaInfo targets of build plugins to load into the CLI.
        mnemonic: The action's mnemonic.
        progress_message: The action's progress message.
    """
    java_runtime = ctx.attr._java_runtime[java_common.JavaRuntimeInfo]
    classpath = depset(transitive = [
        target[JavaInfo].transitive_runtime_jars
        for target in [ctx.attr._cli] + plugins
    ])

    launcher = ctx.actions.args()
    launcher.add(java_runtime.java_executable_exec_path)
    launcher.add_joined(classpath, join_with = ctx.configuration.host_path_separator)

    ctx.actions.run_shell(
        inputs = depset(transitive = [inputs, classpath]),
        outputs = outputs,
        tools = java_runtime.files,
        arguments = [launcher, script_args],
        command = _PROLOGUE + script,
        # Refuse the Maven dependencies a smithy-build.json may declare: every jar the CLI
        # reads is an input of this action.
        env = {"SMITHY_DEPENDENCY_MODE": "forbid"},
        mnemonic = mnemonic,
        progress_message = progress_message,
    )
