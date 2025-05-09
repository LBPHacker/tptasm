# TPTASM

## What?

A universal assembler for TPT computers that aims to be as architecture-agnostic
as possible and to support all computers ever made in TPT. If you're aware of
one that I've missed, open an issue.

Computers currently supported (in alphabetical order):

- [A728D280](https://powdertoy.co.uk/Browse/View.html?ID=2460726) and
  [A728D28A](https://powdertoy.co.uk/Browse/View.html?ID=2460726) by Sam_Hayzen
- [B29K1QS60](https://powdertoy.co.uk/Browse/View.html?ID=2435570) by unnick
- [I8M7D28S](https://powdertoy.co.uk/Browse/View.html?ID=2473628) by Sam_Hayzen
- [MAPS](https://powdertoy.co.uk/Browse/View.html?ID=975033) by drakide
- [MICRO21](https://powdertoy.co.uk/Browse/View.html?ID=1599945) by RockerM4NHUN
- [PTP7](https://powdertoy.co.uk/Browse/View.html?ID=2458644) by unnick
- [R216K2A](https://powdertoy.co.uk/Browse/View.html?ID=2303519),
  [R216K4A](https://powdertoy.co.uk/Browse/View.html?ID=2305835) and
  [R216K8B](https://powdertoy.co.uk/Browse/View.html?ID=2342633) by LBPHacker
- [R3A1016](https://powdertoy.co.uk/Browse/View.html?ID=3236906) et al by LBPHacker
- Armatoste (unreleased, under development) by DanielUbTb

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

| position | name   | type                     | description                  |
| -------- | ------ | ------------------------ | ---------------------------- |
| 1        | source | string                   | path to source to assemble   |
| 2        | target | integer, string or table | identifier of the target CPU |
| 3        | log    | string or handle         | path to redirect log to      |
| 4        | model  | string                   | model number                 |
| | silent          | any     | don't log anything                            |
| | anchor          | string  | spawn anchor for specified model              |
| | anchor\_dx      | integer | X component of anchor direction vector        |
| | anchor\_dy      | integer | Y component of anchor direction vector        |
| | anchor\_prop    | string  | name of property for anchor to use            |
| | anchor\_id      | integer | CPU identifier to encode in the anchor        |
| | detect          | any     | list recognisable CPUs with model and ID      |
| | export\_labels  | string  | path to export labels to                      |
| | allow\_model\_mismatch | any | throw only warnings instead of errors      |

There's also a way to pass arguments by simply passing a table as the first
argument. In this case its integer-keyed pairs will become the positional
arguments (the ones that adhere to Lua's definition of arrays anyway) and
all other pairs become named arguments. Don't worry, the examples below will
make all this clear.

### Notes on arguments

- `target` may be a string, in which case the opcodes are dumped into the file
  this string refers to, in little endian encoding (refer to the corresponding
  architecture module for number of bytes in such an opcode; generally it will
  be the opcode width passed to `opcode.make` multiplied by 4)
- `target` may be a table, in which case the opcodes are copied into it and
  no flashing attempts occur (useful when you're using TPTASM outside TPT)
- if `target` is not specified, the assembler looks for the first CPU that
  matches the model name passed (or any CPU if it wasn't passed); if the anchor
  particle of a CPU happens to be directly under your TPT cursor, it's selected
  as the target
- `log` may also be an object with a `:write` method (e.g. a file object), in
  which case output is redirected to that object by means of calling `:write`
  (`:close` is never called and doesn't have to be present)
- `silent` and `allow_model_mismatch` are checked for truthiness by Lua's
  definitions, so they're considered true if they're not `false` or `nil`
  (likewise, useful when you're using TPTASM outside TPT)
- `(anchor_dx, anchor_dy)` defaults to the vector `(1, 0)`, as anchors are
  generally horizontal and are read from the left to the right
- `anchor_prop` defaults to `"ctype"`, as anchors tend to be lines of FILT,
  which can be easily located visually if they contain ASCII data

### Inside TPT

Install the [Script Manager](https://powdertoy.co.uk/Discussions/Thread/View.html?Thread=19400),
then install [TPTASM](https://starcatcher.us/scripts?view=316) with it. Once done, usage is as simple as:

```lua
-- install TPTASM with the script manager
-- see https://starcatcher.us/scripts?view=316
tptasm("/path/to/source.asm") -- assemble source
tptasm("/path/to/source.asm", 0xDEAD) -- specify target CPU
tptasm("/path/to/source.asm", nil, "log.log") -- specify file to log output to
tptasm("/path/to/source.asm", nil, nil, "R3") -- specify model name
```

For example, download [micro21/demo.asm](examples/micro21/demo.asm), navigate to
[save id:1599945](https://powdertoy.co.uk/Browse/View.html?ID=1599945) and
execute this:

```lua
tptasm("/path/to/downloads/micro21/demo.asm") -- adjust /path/to/downloads to match your system
```

Advanced functionality example:

```lua
-- let's say this is not TPT's console but some script executed in TPT by some other means
opcodes = {}
tptasm({ source = "/path/to/source.asm", target = opcodes, model = "R3" })
print(opcodes[0x1337]:dump())
```

### Somewhere else, for normal usage

Download the latest release and use `loadfile` to get access to the `tptasm`
function in any Lua environment:

```lua
tptasm = loadfile("/path/to/tptasm.lua")
```

Releases from this repo are also what get published on the Script Manager, so
if you have already installed TPTASM with the Script Manager, you can just use
it directly from TPT's data folder.

Command line usage is also possible:

```
$ luajit /path/to/tptasm.lua ...
```

### Somewhere else, for development purposes

Assuming the current directory is this repo, submodules have been fetched with
`git submodule update --init`, and [LuaJIT](https://luajit.org/) or some other
Lua 5.x version has been installed:

```sh
# currently quite pointless to do but possible nonetheless
$ luajit TPT-Script-Manager/modulepack.lua modulepack.conf run /path/to/source.asm model=R3
```

TPTASM can be run from other current directories by passing modulepack.lua and
modulepack.conf with appropriately relative or absolute paths.

### Exporting labels

The file referred to by `export_labels` will look something like this
(see [examples/micro21/demo.asm](examples/micro21/demo.asm)):

```
start 0x0
start.jump_table 0x6
demo_addition 0x2C
demo_odds 0x33
demo_odds.get_number 0x34
demo_odds.get_number.done 0x3A
demo_odds.count_odds 0x3B
...
```

That is, it'll have one fully qualified label and the corresponding address
in hexadecimal per line, separated by one space character.

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
