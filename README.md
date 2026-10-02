# rules_smithy

Bazel rules for [Smithy](https://smithy.io) models, as a Bazel module (bzlmod, Bazel 9).

The rules run the Smithy CLI (`software.amazon.smithy:smithy-cli`, version `SMITHY_VERSION`
in `MODULE.bazel`) in actions. The CLI and the build plugins it loads run in one JVM, so they
are resolved together in this module's own Maven resolution (`maven_install.json`) and never
mix with the consuming build's. Every jar the CLI reads is an action input:
`SMITHY_DEPENDENCY_MODE=forbid` refuses Maven dependencies a smithy-build.json declares.

## Setup

```starlark
bazel_dep(name = "rules_smithy", version = "0.0.0")
```

with an override naming where the module lives, for example
`local_path_override(module_name = "rules_smithy", path = "vendor/smithy-bazel-rules")`.

## Rules

Load them from `@rules_smithy//smithy:defs.bzl`.

### `smithy_library`

Validates a model and packages it as a jar with a `META-INF/smithy` manifest. The jar is a
model dependency of the other rules and, through its `JavaInfo`, of any tool that discovers
models from jars, such as a code generator taking model jars.

```starlark
smithy_library(
    name = "weather_model",
    srcs = glob(["model/**/*.smithy"]),
    deps = ["@rules_smithy//smithy:aws_traits"],
)
```

`deps` are `smithy_library` targets or published model jars (any `JavaInfo` target, such as a
trait package from Maven). A published jar contributes only itself; the CLI provides the
Java dependencies its trait classes need. Model jars are discovered through their own
classloader, so they never put a second Smithy version on the CLI's classpath.

### `smithy_build`

Runs one plugin of one projection of a smithy-build.json, and outputs what the plugin wrote
as a directory. Plugins that do not ship with the CLI are loaded with `plugins`.

```starlark
smithy_build(
    name = "weather_rust_client",
    srcs = glob(["model/**/*.smithy"]),
    config = "smithy-build.json",
    projection = "rust-client",
    plugin = "rust-client-codegen",
    plugins = ["@rules_smithy//smithy/plugins:rust_client_codegen"],
    deps = ["@rules_smithy//smithy:aws_traits"],
)
```

The directory of a code generator is a source tree: rules_rust compiles one with
`rust_library(srcs = [":weather_rust_client"], root_path = "src/lib.rs", ...)`.

### `smithy_ast`

Writes the model, with the model libraries it builds on, as one JSON AST file (`flatten`
removes mixins).

## Provided targets

| Target | What it is |
| --- | --- |
| `//smithy:aws_traits` | The AWS trait definitions (`aws.protocols#restJson1`, ...), a model library |
| `//smithy/plugins:rust_client_codegen` | smithy-rs's `rust-client-codegen` plugin |
| `//smithy/validation:validators` | Style validators; depending on the library applies them |

## Development

`bazel test //test:rules_test` builds every rule on the test models. This module's own builds
run on the JDK `.bazelrc` selects, rules_java's OpenJDK 25. After changing a Maven artifact, run
`REPIN=1 bazel run @rules_smithy_maven//:pin`.
