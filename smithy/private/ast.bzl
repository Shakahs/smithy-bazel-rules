"""smithy_ast: a Smithy model as one JSON AST file."""

load(":cli.bzl", "CLI_ATTRS", "MODEL_ATTRS", "model_jars", "run_smithy")

# `smithy ast` has no model discovery, so the model jars are loaded as models themselves.
_SCRIPT = """
output="$1"; shift
smithy ast "$@" > "$output"
"""

def _smithy_ast_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    dependencies = model_jars(ctx.attr.deps)

    args = ctx.actions.args()
    args.add(output)
    if ctx.attr.flatten:
        args.add("--flatten")
    args.add_all(ctx.files.srcs)
    args.add_all(dependencies)

    run_smithy(
        ctx,
        script = _SCRIPT,
        script_args = args,
        outputs = [output],
        inputs = depset(ctx.files.srcs, transitive = [dependencies]),
        mnemonic = "SmithyAst",
        progress_message = "Writing the JSON AST of %{label}",
    )

    return [DefaultInfo(files = depset([output]))]

smithy_ast = rule(
    implementation = _smithy_ast_impl,
    doc = "Writes a Smithy model, with the model libraries it builds on, as one JSON AST file.",
    attrs = MODEL_ATTRS | CLI_ATTRS | {
        "flatten": attr.bool(
            doc = "Flatten the model and remove its mixins.",
        ),
    },
)
