# TPTASM

## What?

A universal assembler for TPT computers that aims to be as architecture-agnostic
as possible and to support all more important (if not all, period) computers
ever made in TPT.

Computers currently supported (in alphabetical order):

- [A7-28D28 Microcomputer](https://powdertoy.co.uk/Browse/View.html?ID=2460726) by Sam_Hayzen
- [B29K1QS60](https://powdertoy.co.uk/Browse/View.html?ID=2435570) by unnick
- [Micro Computer v2.1](https://powdertoy.co.uk/Browse/View.html?ID=1599945)
  by RockerM4NHUN
- Generic R3 (unreleased, under development) by LBPHacker

## Why?

Because I finally made an assembler with nice enough features that it probably
makes sense to not make another one but just support all future (and past)
computers with this one instead.

## How?

[Click here for TL;DR](#tldr), if you don't feel like reading all this.

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
| | silent          | any     | don't log anything                        |
| | anchor          | string  | spawn anchor for specified model          |
| | anchor_dx       | integer | X component of anchor direction vector    |
| | anchor_dy       | integer | Y component of anchor direction vector    |
| | anchor_prop     | string  | name of property for anchor to use        |
| | anchor_id       | integer | CPU identifier to encode in the anchor    |
| | detect          | any     | list recognisable CPUs with model and ID  |

There's also a way to pass arguments by simply passing a table as the first
argument. In this case its integer-keyed pairs will become the positional
arguments (the ones that adhere to Lua's definition of arrays anyway) and
all other pairs become named arguments. Don't worry, the examples below will
make all this clear.

### Notes on arguments

- `target` is implicitly converted to an integer if it's a string
- `target` may be a table, in which case the opcodes are copied into it and
  no flashing attempts occur (useful when you're using TPTASM outside TPT)
- if `target` is not specified, the assembler looks for the first CPU that
  matches the model name passed (or any CPU if it wasn't passed); if the anchor
  particle of a CPU happens to be directly under your TPT cursor, it's selected
  as the target
- `log` may also be an object with a `:write` method (e.g. a file object), in
  which case output is redirected to that object by means of calling `:write`
  (`:close` is never called and doesn't have to be present)
- `silent` is checked for truthiness by Lua's definitions, so it's considered
  true if it's not `false` or `nil`
  (likewise, useful when you're using TPTASM outside TPT)
- `(anchor_dx, anchor_dy)` defaults to the vector `(1, 0)`, as anchors are
  generally horizontal and are read from the left to the right
- `anchor_prop` defaults to `"ctype"`, as anchors tend to be lines of FILT,
  which can be easily located visually if they contain ASCII data

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

### TL;DR

Steps to take if you have no idea what's going on and just want to finally
program a computer:

1. [click here](https://raw.githubusercontent.com/LBPHacker/tptasm/master/src/tptasm.lua);
   this will either take you to a new page with a lot of text, or it will
   make your browser automatically download a file named `tptasm.lua`
1. if you end up on the page with a lot of text, try `right click -> Save As` or
   `Ctrl+S` (or whatever floats your boat); this _really_ should make your
   browser automatically download said file (or it may ask you where you want to
   save it and under what name; leave it `tptasm.lua` and _make sure_ the file
   is actually called `tptasm.lua` and not something stupid like
   `tptasm.lua.txt`)
1. save said file to wherever you have TPT installed, preferably next to the
   Saves folder
1. have the code you want to assemble saved to a file (say, `code.asm`), and
   have said file also next to the Save folder
1. open the save in TPT with the computer you want to program
1. if there are multiple computers in the save, find the one and only QRTZ
   particle in the computer you want to program (possibly with the Find mode,
   `Ctrl+F`) and move your cursor over it (use a `1x1` brush)
1. open the console (with `~` or the `[C]` button on the right side of the
   window) and execute the following:

   ```lua
   loadfile("tptasm.lua")("code.asm")
   ```

1. if `[tptasm] done` is not the only thing you see, you may want to save the
   log to a file for inspection; you can do this by executing this instead:

   ```lua
   loadfile("tptasm.lua")("code.asm", nil, "log.log")
   ```

   ... which will create a file named log.log next to your Saves folder with
   messages explaining why your code failed to be assembled
1. if your code assembles, you're done!
1. if the log shows something like "this is an error, tell LBPHacker", then
   tell me!


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
