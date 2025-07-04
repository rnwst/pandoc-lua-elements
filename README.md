# pandoc-lua-elements

`pandoc-lua-elements` is a [pandoc](https://pandoc.org/) [Lua filter](https://pandoc.org/lua-filters.html) which executes Lua CodeBlocks and inline Code elements in a document and replaces them with their return values, similar to how Lua filters manipulate document elements. This enables inclusion of dynamically generated document content.


## Usage

```console
pandoc input.md -L pandoc-lua-elements/init.lua
```

> [!CAUTION]
> `pandoc-lua-elements` executes arbitrary code. Only run this filter on documents you trust.


### Running Lua code

To execute Lua CodeBlocks, the frontmatter key `lua-elements` needs to be set
to `true`:
```md
---
author: R. N. West
title: Dynamically Generated Documents with Lua!
lua-elements: true
---

Document content...
```
Code blocks and inline Code elements with class `lua` will then be executed and replaced with their return values, similar to how filters act on document elements:
````md
A CodeBlock:

```lua
pi = 3.14
return pandoc.Para('Hello world!')
```

The number π is `pandoc.Str(pi)`{.lua}.
````
which, when outputting to the `plain` format, results in
> ```
> A CodeBlock:
>
> Hello world!
>
> The number π is 3.14.
> ```

To prevent execution of Lua code, set the `exec` attribute to `false`:
````md
```{.lua exec=false}
-- This code is not executed!
io.stderr:write('An error message.')
```

Consider the function `some_lua_function(foo, bar)`{.lua exec=false}.
````

CodeBlocks and inline Code elements must return a Block or Inline AST element respectively or a list of such elements. CodeBlocks may also return `nil`. Returning `nil` will remove the CodeBlock from the AST; unlike in Lua filter functions, where a return value of `nil` indicates that the AST element should remain unchanged. Inline Code elements are not allowed to evaluate to `nil`, as this is usually indicative of a bug. Furthermore, inline Code elements may also evaluate to a `number` or `string` instead of an Inline AST element, allowing the above example to be rewritten more elegantly as
```md
The number π is `pi`{.lua}.
```


## License

© 2025 R. N. West. Released under the [GPL](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html) version 2 or greater. This software carries no warranty of any kind.
