# Bld

Bld is a simple odin builder interface

```odin
main :: proc() {
    build_cmd := bld.new_command("build")
    add_artifact(build_cmd, {
        name =       "example",
        build_mode = .Exe,
        root =       "src",
        optim =      .Speed,
        target =     .Release,
        compiler =   .Odin,
    })

    process_commands({ build_cmd })
}

```
