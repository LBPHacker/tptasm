# TPTASM

## What?

A universal assembler for TPT computers that aims to be as architecture-agnostic
as possible and to support all more important (if not all, period) computers
ever made in TPT.

Computers currently supported:

- [B29K1QS60](https://powdertoy.co.uk/Browse/View.html?ID=2435570) by unnick
- [Micro Computer v2.1](https://powdertoy.co.uk/Browse/View.html?ID=1599945)
  by RockerM4NHUN
- Generic R3 (unreleased, under development) by LBPHacker

## Why?

Because I finally made an assembler with nice enough features that it probably
makes sense to not make another one but just support all future (and past)
computers with this one instead.

## How?

You can run the assembler from TPT or really in any environment that's
compatible with Lua 5.1. Running it from TPT has the benefit of actually
allowing you to program computers.

The assembler takes both positional and named arguments. A positional string
argument of the format `key=value` (`^([^=]+)=(.+)$`, to be precise) becomes
a named argument, its name is set to `key` and its value to `value`, both
strings. The remaining positional arguments become the final positional
arguments.

All positional arguments have equivalent named counterparts.

| position | name   | type             | description                      |
| -------- | ------ | ---------------- | -------------------------------- |
| 1        | source | string           | path to source to assemble       |
| 2        | target | table or integer | identifier of the target CPU     |
| 3        | log    | string or any    | path to redirect log to          |
| 4        | model  | string           | model number                     |
|          | silent | any              | don't log anything               |
|          | anchor | string           | spawn anchor for specified model |

There's also a way to pass arguments by simply passing a table as the first
argument. In this case its integer-keyed pairs will become the positional
arguments (the ones that adhere to Lua's definition of arrays anyway) and
every other pairs become named arguments. Don't worry, the examples below will
make all this clear.

### Notes on arguments

- `target` is implicitly converted to an integer if it's a string
- `target` may be a table, in which case the opcodes are copied into it and
  no flashing attempts occur
  (useful when you're using TPTASM outside TPT)
- `log` may also be an object with a `:write` method (e.g. a file object), in
  which case output is redirected to that object by means of calling `:write`
  (`:close` is never called and doesn't have to be present)
- `silent` is checked for truthiness by Lua's definitions, so it's considered
  true if it's not `false` or `nil`
  (likewise, useful when you're using TPTASM outside TPT)

### Inside TPT

```lua
tptasm = loadfile("tptasm.lua") -- load tptasm into memory as a function
     -- (this assumes you saved it in the same directory TPT is in)
tptasm("/path/to/source.asm") -- assemble source
tptasm("/path/to/source.asm", 0xDEAD) -- specify target CPU
tptasm("/path/to/source.asm", nil, "log.log") -- specify file to log output to
tptasm("/path/to/source.asm", nil, nil, "R3") -- specify model name
```

#### Complete example

Assuming this repository has been cloned to `~/Development/tptasm`, navigate to
[save id:1599945](https://powdertoy.co.uk/Browse/View.html?ID=1599945) and
execute this:

```lua
loadfile("~/Development/tptasm/tptasm.lua")("~/Development/tptasm/examples/micro21/demo.lua")
```

### Somewhere else

```sh
# currently quite pointless to do but possible nonetheless
$ ./tptasm.lua /path/to/source.asm model=R3
```

```lua
-- let's say this is not TPT's console
tptasm = loadfile("tptasm.lua")
opcodes = {}
tptasm({ source = "/path/to/source.asm", target = opcodes, model = "R3" })
print(opcodes[0x1337]:dump())
```

## Then?

Things I still want to do but don't know when I'll have the time:

- [ ] support Harvard architecture computers more, as currently there is no
      way to address their memory through labels, only preprocessor macros
      (`%define`, `%eval`, etc.)
- [ ] clean up and comment code as much as possible
- [ ] add support for more computers
- [ ] possibly replace postfix syntax in expression blocks (`{ }` blocks) with
      infix syntax
- [ ] possibly add support to recognise expression blocks and implicitly
      evaluate them at assemble time, thus eliminating the need to wrap them in
      curly brackets
- [ ] check if this thing works on Windows at all and fix it if it doesn't

PRs are welcome, especially if they add support for computers. Yes, I do realise
my code is a huge mess. Good luck figuring it out.
