[English](README.md) | **简体中文**

# MoonJSON Toolkit

一个 MoonBit 写的 JSON 工具箱：格式化、校验、诊断、分析并可视化 JSON 文档。它由
一个命令行工具和一个小型 Web 仪表盘组成，后者用来把工具写出的统计结果画成图。

![统计仪表盘](./frontend/screenshot.png)

## 功能特性

- **格式化** —— 以每层 0 到 16 个空格美化打印任意 JSON 文档。空容器保持在一行内，
  字符串按规则转义，数字保留输入中的原始字面量。`--compact` 改为把整份文档压到一
  行，`--sort-keys` 在打印前对每个对象的键排序，`--trim-strings` 去掉每个字符串值
  两端的空白，而字符串内部的空格原样保留。
- **一次处理多份文档** —— `--file` 可以重复。每个文件依次处理，多于一个时各自带一
  行 `==> path <==` 表头，某个文件出错不会影响后面的文件。
- **JSON Lines** —— `--jsonl` 把输入当作「一行一个文档」来读，每条记录打印到自己的
  一行上。某一行不是合法 JSON 时会带上它在文件中的行号报错，其余记录照常打印。
- **重塑结构** —— `--flatten` 把每层嵌套对象压成点号键，`{"a":{"b":1}}` 变成
  `{"a.b":1}`；`--unflatten` 再把它们展开回去。两者都会深入数组里的对象，也都会拒绝
  一份把同一条路径写成两种样子的文档，并点名那两个互相矛盾的键。
- **修剪** —— `--prune-null` 删掉所有值为 `null` 的对象成员，`--prune-empty` 删掉所有
  空对象和空数组，以及因此变空的容器。两者可以一起给，null 先删，所以
  `{"a":{"b":null}}` 一趟就变成 `{}`。
- **校验与诊断** —— 格式错误的文档会报告行、列和原因，并指出出错的那个字符：

  ```
  error: <stdin> is not valid JSON
  line 1, column 8: expected opening quote
    {"a":1,}
           ^
  ```

  同一个对象里出现重复键同样算错误，报在键的第二次书写处，并指出第一次出现在哪一
  行哪一列 —— 悄悄保留其中一个，等于让你拿到的值取决于解析器而不是文档本身。
  `--max-depth <n>` 对嵌套深度做同样的约束：比 `n` 更深的文档一律拒绝，并指出它在
  哪里超了。
- **路径与键** —— `--paths` 逐行列出文档中每个值的路径，`--keys-only` 只列出对象成
  员。两者合起来回答「这里面有什么」，而不用把文档打印出来。

- **统计** —— 键数量、节点数量、最大嵌套深度、JSON 类型分布以及按深度分层的分布，
  由 `--json-out` 写成 JSON，或由 `--stats` 打印成两行摘要。
- **颜色** —— 在终端上给错误上色，其它情况一律不着色，所以重定向后的输出里永远不会
  混进转义序列。`--no-color` 可以关掉颜色，`NO_COLOR` 和 `TERM=dumb` 这两个约定也
  一样有效。
- **图表** —— 一个 [Rabbita](https://github.com/moonbit-community/rabbita) Web 应用把
  统计文件渲染成顶层键数量柱状图、嵌套深度饼图和类型表格。
- **AI 评审** —— `--ai` 把格式化后的文档发给 DeepSeek，打印一份质量报告和重构建议。

## 环境要求

- [MoonBit 工具链](https://www.moonbitlang.com/download/)（本项目基于
  `moon 0.1.20260915` 开发）。
- native 目标。HTTP 客户端和异步运行时只有 native 版本，所以命令行工具构建的是
  `native` 而不是 `wasm`。

## 安装

```sh
git clone https://github.com/BigSaltyMan/moonjson-toolkit.git
cd moonjson-toolkit
moon build --target native
```

依赖在 `moon.mod` 里声明，由 `moon build` 自动拉取：

```sh
moon add Nanaloveyuki/parsec   # parser combinators, with a JSON grammar
moon add oboard/mio            # HTTP client used by --ai
```

## 用法

下面这段就是 `--help` 的真实输出（原文照录，未作翻译）：

```
moonjson-toolkit - format, validate and analyse JSON documents

Usage:
  moonjson-toolkit [options]

Input is read from standard input unless --file is given.

Options:
  -f, --file <path>      Read one or more input files instead of standard input
  -i, --indent <n>       Spaces per nesting level, 0 to 16 (default: 2)
  -c, --compact          Print the document on one line, ignoring --indent
  -S, --sort-keys        Order the keys of every object before printing
      --trim-strings     Trim the whitespace around every string in the document
      --flatten          Collapse every nested object into dotted keys
      --unflatten        Expand every dotted key back into nested objects
      --prune-null       Remove every object member whose value is null
      --prune-empty      Remove every empty object and every empty array
      --jsonl            Read the input as JSON Lines, one document per line
      --max-depth <n>    Refuse documents nested deeper than <n> (default: 128)
      --paths            Print the path of every value instead of the document
      --keys-only        Print only the paths that name an object member
  -v, --validate         Only check the input and report the first error
  -h, --help             Show this message and exit
  -V, --version          Show the version and exit
      --ai               Ask DeepSeek for a quality report and suggestions
      --json-out <path>  Write a statistics report as JSON to <path>
      --stats            Print a statistics summary instead of the document
      --no-color         Never colour the output, even on a terminal

Short options may be combined, so -vh means -v -h. The value of --indent
may be attached, as in -i4, -i=4, --indent=4 or --indent 4.

--file may be repeated. Each file is handled in turn, each under a
'==> path <==' heading once more than one is given, and the run exits with
the first non-zero code among them.

--paths and --keys-only each replace the printed document with a list of
names, one per line. Asking for both prints the longer list, and -v wins
over either of them, since it asks for no document output at all.

--stats replaces the document with a two-line summary of it. It joins the
same family: -v wins over it as it wins over the name lists, and --json-out
takes precedence over it, so asking for both writes the file and prints the
document as usual. --json-out describes one document, so it is refused when
several files are named.

--flatten collapses every nested object into dotted keys, and --unflatten
expands them again. The two are inverses of each other, so only one of them
may be given. A document that names one path two ways, with a key "a.b"
beside a key "a", has no flattened or unflattened form and is refused with
both keys named.

--prune-null drops every object member whose value is null, and --prune-empty
drops every empty object and every empty array, then the containers left empty
by that in turn. The two are independent and may be given together, in which
case the nulls go first, so a member left holding {} is dropped as well.
--prune-null keeps every item of an array: a null in an object is a member with
no value, while a null in an array is a value in a place, and dropping it would
renumber the items after it.

--jsonl reads the input as JSON Lines: one document per line, with blank
lines skipped. Each record is handled on its own, so the other options apply
to every one of them in turn. A record that is not valid JSON is reported
with its line in the file and the rest are still printed; the run exits 1 if
any record failed. It describes many documents at once, so it is refused
with --json-out and with --ai.

Exit codes:
  0  success
  1  the input could not be read, or is not valid JSON
  2  the command line was invalid
  3  the input was valid but the AI review failed
```

短选项可以合并，`-vh` 就是 `-v -h`。`--indent` 的值可以贴着写，即 `-i4`、`-i=4`、
`--indent=4` 或 `--indent 4` 都可以。

注意 `-v` 和 `-V` 是两个不同的选项：小写的做校验，大写的打印版本号。

`-v` 把格式化后的文档换成一行结论，也只改这一件事：`--json-out` 和 `--ai` 照常执行。
`--help` 和 `--version` 则完全不读输入就给出回答。

`--paths` 和 `--keys-only` 同样替换掉文档，换成的是一串名字而不是结论。两个都要时打
印更长的那份，而 `-v` 又压过它们俩，因为它要求的是一点文档输出都不要。和 `-v` 一
样，这两个也不会中止其余的工作：`--json-out` 和 `--ai` 照常执行。

`--stats` 把文档换成两行摘要。它属于同一族：`-v` 压过它，跟压过那两份名字列表一样；
`--json-out` 又优先于它，所以两个都问就写文件、照常打印文档。

`--file` 可以重复，每份文档各自独立处理。`--json-out` 描述的是单份文档，所以给了多个
文件时会直接拒绝，而不是只给最先读到的那份写文件。

`--jsonl` 声明的是输入**是什么**，而不是要拿它做什么：每一行都当成一份独立文档来读，
其余选项依次作用于每一条记录，所以 `--compact`、`--sort-keys`、`--trim-strings` 到达
每条记录的方式，和它们到达单份文档的方式完全相同。空行会跳过。`--json-out`、`--ai`、
`--stats`、`--paths`、`--keys-only` 问的都是关于**一份**文档的问题，而一份 JSON Lines
输入是很多份文档，所以它们会被拒绝，而不是对每条记录重复一遍却说不清哪个答案属于哪
条记录。`-v` 不在其中：它问的是输入是否有效，这对一份装着很多文档的文件来说，和装在
一份文档里的文件一样是个好问题。

`--flatten` 和 `--unflatten` 互为逆运算，所以同时给出它们不是两项改动，而是一个「到
底要哪个」的问题，命令行会被拒绝。一份能两读的文档就按两读来回答：`{"a":{"b":1}}` 和
`{"a.b":1}` 是同一份文档的两种写法，两个选项各把其中一种改写成另一种。它们都不凭空
造出或丢掉东西 —— 压平只是把原本就写着的键拼起来，展开只是在点上把它们拆开 —— 所以
值、值的顺序、乃至空容器，都能活着走完这一趟。

把一条路径写成两种样子的文档，就没有压平后的形式可言。如果某个成员叫 `a.b`，而它旁
边一个叫 `a` 的兄弟装着对象，那么把 `a` 抬起来就会产生第二个 `a.b`，两个之中必须丢掉
一个；这时运行以 `1` 退出，而不是定一条「谁更不重要」的规则替用户决定。两个键都会被
点名，所以消息会告诉你该调解哪一对：

```
error: <stdin> cannot be flattened
conflicting keys: "a" and "a.b"
```

`--unflatten` 同样拒绝这些形状，而且更严格：它只看键，所以一个键只要构成另一个键的
点号前缀，就意味着同一个位置被命名了两次，无论较短的那个键上装着什么值。反过来，字
面量的点号键旁边如果放着别的东西，就完全不是问题，因为没有任何东西被抬起来，也就没
有任何东西会撞上：`{"a.b":1,"a":2}` 压平后还是它自己。

`--prune-null` 和 `--prune-empty` 删掉文档不需要的东西，两者彼此独立，和其它选项也互
不相干，所以可以一起给，也可以单独给。前者删掉所有值为 `null` 的对象成员：一个装着
`null` 的成员，表达的信息不比这个成员不存在更多。后者删掉所有空对象和空数组，而这些
删除留下的空容器也一并删掉，一路往上到哪儿算哪儿。文档本身不是谁的成员，所以即使一
轮跑下来把东西全修剪光了，打印的仍是 `{}` 而不是什么都不打。

`--prune-null` 不碰数组。数组是一个序列，各项的位置本身就是它表达的一部分，所以数组
中间的 `null` 是「某个位置上的值」，删掉它会让它后面所有项重新编号 —— 这也正是
`--prune-empty`（它的全部工作就是删东西）会伸进数组里删掉其中的空容器的原因。两个选项
同时给出时，先删 null：`{"a":{"b":null}}` 在装着 null 的成员变空、又被 `--prune-empty`
取走之后就是 `{}`，而反过来做会停在 `{"a":{}}`。

`--flatten`、`--unflatten`、`--prune-null`、`--prune-empty`、`--sort-keys` 和
`--trim-strings` 改的是文档而不是它的排版，所以这一轮运行中的其它环节看到的都是改完的
结果：打印出来的文档、路径列表、AI 评审，以及 `--stats` 和 `--json-out` 背后的计数 ——
后者描述的是这一轮**产出**的文档，而不是读进来的那份。排序和去空白分不出区别（两者都
不移动值、也不改变类型），但修剪和重塑能看出来，而一份还在数着文档已经不再拥有的成员的
摘要，描述的是读者看不到的东西。

### 退出码

| 码 | 含义 |
| ---- | ------- |
| `0`  | 输入已格式化，或校验通过 |
| `1`  | 输入读不出来，或者不是合法 JSON |
| `2`  | 命令行本身有误 |
| `3`  | 输入是合法的，但 AI 评审没能产出 |

运行失败时，对于出错的那份文档，标准输出上什么都不会写。单份文档所有可能失败的步骤都
发生在它第一个字节被打印之前，所以失败永远不会留下半份文档给正在读输出的下游。多个文件
时这条保证逐文件成立：成功的照常打印，失败的在标准错误上，退出码取第一个非 `0` 的。
`--jsonl` 下则逐记录成立，因为记录才是「要么解析得出、要么解析不出」的单位；只要出现过
任何一条坏记录，这一轮就以 `1` 退出，不管后面还有多少条好的。

### 示例

用默认的两个空格缩进格式化一个文件：

```sh
moon run cmd/main -- -f test.json
```

```json
{
  "name": "moonjson-toolkit",
  "version": 2,
  "stable": true,
  "tags": [
    "json",
    "cli",
    "formatter"
  ],
  "owner": {
    "name": "MoonBit",
    "contact": {
      "email": "dev@moonbitlang.com",
      "active": true
    }
  },
  "dependencies": [
    {
      "name": "parsec",
      "version": "0.1.3"
    },
    {
      "name": "async",
      "version": "0.22.1"
    },
    {
      "name": "x",
      "version": "0.5.5"
    }
  ],
  "settings": {
    "indent": 2,
    "theme": null
  }
}
```

一轮处理多份文档。每份各自格式化，带一行说明它来自哪个文件的表头，而表头只在有多份
文档需要区分时才出现：

```sh
moon run cmd/main -- -f a.json -f b.json
# ==> a.json <==
# {
#   "a": 1
# }
# ==> b.json <==
# {
#   "b": 2
# }
```

读不出或解析不了的文件不会中止整轮运行。它的错误进标准错误，下一个文件照常处理，所以
一个坏输入不会把其余的藏起来；这一轮随后以第一个非 `0` 的码退出，这里是 `1`：

```sh
moon run cmd/main -- -f a.json -f c.json -f b.json
# ==> a.json <==
# {
#   "a": 1
# }
# ==> b.json <==
# {
#   "b": 2
# }
# error: c.json is not valid JSON
# line 1, column 8: expected opening quote
#   {"c":3,}
#          ^
```

格式化一份「每行一个文档」的文件，日志和导出数据通常就是这个形状。每条记录打印在自己
的一行上，而空行不是记录：

```sh
printf '{"a":1}\n\n{"b":[2]}\n' | moon run cmd/main -- --jsonl
# {
#   "a": 1
# }
# {
#   "b": [
#     2
#   ]
# }
```

一行坏掉不会让读者失去其余的。它带着自己在文件中的行号报到标准错误上，而每一条读得出
的记录照常打印；这一轮随后以 `1` 退出：

```sh
printf '{"a":1}\n{"b":1,}\n{"c":3}\n' | moon run cmd/main -- --jsonl -c
# {"a":1}
# {"c":3}
# error: <stdin> is not valid JSON
# line 2, column 8: expected opening quote
#   {"b":1,}
#          ^
```

去掉混进文档字符串里的空白。只有字符串两端会被动到，所以内部的空格属于字符串本身，留着：

```sh
printf '{"name":"  moon  ","note":"  a  b  "}' | moon run cmd/main -- --trim-strings -c
# {"name":"moon","note":"a  b"}
```

键是名字而不是值，原样保留。去键上的空白等于改名，而两个只差首尾空格的键会撞成解析器
拒绝的重复键 —— 一份本来能解析的文档会变成不能解析的。

把文档的嵌套压成点号键，这是交给任何「读一张扁平名字表」的东西时该有的形状：

```sh
printf '{"a":{"b":{"c":1}},"d":[{"e":{"f":2}}]}' | moon run cmd/main -- --flatten -c
# {"a.b.c":1,"d":[{"e.f":2}]}
```

再展开回去，过程中把共享前缀的键合并起来：

```sh
printf '{"a.b":1,"a.c":{"d":2}}' | moon run cmd/main -- --unflatten -c
# {"a":{"b":1,"c":{"d":2}}}
```

把一条路径写成两种样子的文档，两个方向都没有可得的形态，会被拒绝并点名两个键：

```sh
printf '{"a":{"b":1},"a.b":2}' | moon run cmd/main -- --flatten -c
# error: <stdin> cannot be flattened
# conflicting keys: "a" and "a.b"
```

字面量点号键旁边放着别的东西则不属于这种情况：`a` 里没有任何东西被抬起来，也就没有
东西会撞上，这份文档本来就是平的。

删掉文档没说的事：装着 `null` 的成员，以及什么都没装的容器。两者可以叠加，而 null 先
删，所以被删空的成员也会跟着走：

```sh
printf '{"a":null,"b":{},"c":[1,null],"d":{"e":null}}' | moon run cmd/main -- --prune-null --prune-empty -c
# {"c":[1,null]}
```

数组里的那个 `null` 还在：数组是一个序列，从中间抽掉一项会让后面的项重新编号。空容器
是另一回事，`--prune-empty` 确实会伸进数组里把它删掉。

从管道读入并用四个空格缩进：

```sh
echo '{"a":[1,2]}' | moon run cmd/main -- -i4
```

把文档压到一行并给键排序 —— 当输出是要拿去比较或 diff 而不是阅读时，就该用这一对：

```sh
echo '{"b":{"z":1,"a":2},"a":[{"y":3,"x":4}]}' | moon run cmd/main -- -cS
# {"a":[{"x":4,"y":3}],"b":{"a":2,"z":1}}
```

`--sort-keys` 会作用到文档里的每个对象，包括嵌在数组里的那些，并且按码位比较键，所以
大写字母排在小写字母前面。它改的是打印出来的内容，不是 `--json-out` 记下的内容：统计
文件保留文档本来的书写顺序。

校验一份文档而不打印它：

```sh
moon run cmd/main -- -v -f test.json
# test.json: valid JSON
```

`-v` 抑制的只是格式化后的文档，别的都不抑制：`--json-out` 照常写文件，`--ai` 照常给出
报告。这些组合是能叠加的，所以 `-v --json-out stats.json` 可以在不打印文档本身的情况下
校验它并收集统计：

```sh
moon run cmd/main -- -v --json-out stats.json -f test.json
# test.json: valid JSON
# statistics written to stats.json
```

拒绝一份格式错误的文档（退出码 `1`）：

```sh
printf '{"a":1,}' | moon run cmd/main --
# error: <stdin> is not valid JSON
# line 1, column 8: expected opening quote
#   {"a":1,}
#          ^
```

拒绝一份嵌套过深的文档。默认上限是 128 层；如果你预期的文档都比较浅、再深就是出错，
就把它调低：

```sh
printf '[[[[]]]]' | moon run cmd/main -- --max-depth 3
# error: <stdin> is not valid JSON
# line 1, column 4: nesting depth exceeds limit 3
#   [[[[]]]]
#      ^
```

列出文档里有什么，而不打印它：

```sh
echo '{"name":"x","tags":["a","b"],"owner":{"email":"e"}}' | moon run cmd/main -- --paths
# name
# tags
# tags[0]
# tags[1]
# owner
# owner.email
```

同样的输入用 `--keys-only` 会去掉数组下标、停在 `tags`，因为数组里面的值没有被走到：

```sh
echo '{"name":"x","tags":["a","b"],"owner":{"email":"e"}}' | moon run cmd/main -- --keys-only
# name
# tags
# owner
# owner.email
```

重复键报在第二次书写处，并点名第一次：

```sh
printf '{"a":1,"a":2}' | moon run cmd/main --
# error: <stdin> is not valid JSON
# line 1, column 8: duplicate object key "a" (first defined at line 1, column 2)
#   {"a":1,"a":2}
#          ^
```

格式化文档的同时写出一份统计报告：

```sh
moon run cmd/main -- -f test.json --json-out stats.json
```

```json
{
  "total_keys": 19,
  "total_nodes": 26,
  "max_depth": 4,
  "type_counts": [
    { "kind": "null", "count": 1 },
    { "kind": "boolean", "count": 2 },
    { "kind": "number", "count": 2 },
    { "kind": "string", "count": 12 },
    { "kind": "array", "count": 2 },
    { "kind": "object", "count": 7 }
  ],
  "key_counts": [
    { "name": "name", "count": 0 },
    { "name": "version", "count": 0 },
    { "name": "stable", "count": 0 },
    { "name": "tags", "count": 0 },
    { "name": "owner", "count": 4 },
    { "name": "dependencies", "count": 6 },
    { "name": "settings", "count": 2 }
  ],
  "depth_counts": [
    { "depth": 1, "count": 1 },
    { "depth": 2, "count": 7 },
    { "depth": 3, "count": 10 },
    { "depth": 4, "count": 8 }
  ]
}
```

`key_counts` 数的是每个顶层字段里嵌套的键，所以装着标量或标量数组的字段报 `0` ——
`name`、`version`、`stable` 和 `tags` 都是这样 —— 而 `owner` 报出它两层里的四个键，
`dependencies` 报出它三个条目里的六个。`depth_counts` 从 1 开始，覆盖一直到 `max_depth`
的每一层。

把同一批数字打到标准输出而不是写进文件：

```sh
moon run cmd/main -- --stats -f test.json
# keys: 19  nodes: 26  depth: 4
# type counts: null=1 boolean=2 number=2 string=12 array=2 object=7
```

这两行说的就是上面那份报告的内容，顺序也和它一致，只是文档里没有的类型直接省略，而不是
写成 `=0`。

## 统计仪表盘

仪表盘读的是 `--json-out` 写出的文件。它是 `frontend/` 下一个独立的 MoonBit 模块，用
Rabbita 构建并编译成 JavaScript。

```sh
cd frontend

# 1. Produce the data the page reads.
moon run ../cmd/main -- -f ../test.json --json-out public/stats.json

# 2. Build the browser bundle.
warren build --browser-entry main

# 3. Serve dist/ over HTTP and open it.
python3 -m http.server 8000 --directory dist
```

打开 <http://localhost:8000/> 就能看到顶层键数量的柱状图、嵌套深度分布的饼图和类型
表格。

开发期间改用 `warren dev --browser-entry main`，它会带着热重载伺服这个应用。

[Apache ECharts](https://echarts.apache.org/) 已经 vendor 在
`frontend/public/echarts.min.js`，所以这个页面不需要联网，也不需要 CDN。如果这个文件
不在，`charts.js` 会退回到从 CDN 加载 ECharts。

## AI 评审

`--ai` 向 DeepSeek 请求一份对格式化后文档的评审：

```sh
export DEEPSEEK_API_KEY=sk-...
moon run cmd/main -- --ai -f test.json
```

密钥从 `DEEPSEEK_API_KEY` 环境变量读取，绝不硬编码。评审产出不了时以退出码 `3` 退出，
并把原因打印到标准错误，标准输出保持为空。超过 20 000 字符的文档在发送前会被截断，
请求在 60 秒后超时。

## 项目结构

```
moonjson-toolkit/
├── moon.mod              module metadata and dependencies
├── moon.pkg              the library package and its imports
├── formatter.mbt         pretty-printing
├── flatten.mbt           dotted keys out of nesting, and back again
├── prune.mbt             dropping null members and empty containers
├── jsonl.mbt             splitting a JSON Lines input into records
├── diagnostics.mbt       offsets to line/column, rendered error snippets
├── color.mbt             the colour decision and the escape wrapping
├── cli.mbt               argument parsing and usage text
├── parser.mbt            parsing and file/standard-input reading
├── paths.mbt             the path of every value, and of every object member
├── ai.mbt                the DeepSeek request and response handling
├── stats.mbt             the statistics model and its JSON form
├── runner.mbt            one run of the tool, and the exit codes
├── cmd/main/             the process entry point
└── frontend/             the Rabbita dashboard
    ├── main/main.mbt     the app: model, update and view
    └── public/           index.html, styles.css, charts.js, echarts.min.js
```

每个模块都有配套的 `_wbtest.mbt` 白盒测试。格式化、诊断、参数解析、统计和 AI 响应处理
都不需要联网，所以在任何机器上 `moon test` 都是同一条命令。

## 开发

```sh
moon check --target native   # type-check
moon test  --target native   # 172 tests
moon fmt                     # format

cd frontend
moon test --target js        # 4 tests
```

## 测试覆盖率

`moon test` 可以开启插桩运行，报告测试套件覆盖了每个模块的多少代码：

```sh
moon coverage analyze -- -f summary
```

```
ai.mbt: 58/68
cli.mbt: 138/142
cmd/main/main.mbt: 0/14
color.mbt: 30/33
diagnostics.mbt: 64/79
flatten.mbt: 100/102
formatter.mbt: 151/152
parser.mbt: 261/276
runner.mbt: 150/174
Total: 1093/1181
```

即插桩监视的 1181 个点中有 1093 个被覆盖，占 92.5%。这里的计数单位是源码中的位置而不是行：一行里放下两个表达式就是两个点，其中一个没被执行时，这一行仍会算作已覆盖，所以只要模块里有任意一个点没被执行，它就会出现在上面这段输出里；反过来说，它没有列出的四个模块——`jsonl.mbt`、`paths.mbt`、`prune.mbt` 和 `stats.mbt`——是逐点完整覆盖的。同样的数字按覆盖率从高到低排列：

| 模块 | 覆盖率 |
| ---- | ------ |
| `jsonl.mbt`、`paths.mbt`、`prune.mbt`、`stats.mbt` | 100% |
| `formatter.mbt` | 99.3% |
| `flatten.mbt` | 98.0% |
| `cli.mbt` | 97.2% |
| `parser.mbt` | 94.6% |
| `color.mbt` | 90.9% |
| `runner.mbt` | 86.2% |
| `ai.mbt` | 85.3% |
| `diagnostics.mbt` | 81.0% |
| `cmd/main/main.mbt` | 0% |

`cmd/main/main.mbt` 是唯一一个有意为之的零：它是进程入口，而 `moon test` 从不运行 `main`。它做的事只是把真实的命令行和两个真实的数据流交给 `run`，而 `run` 本身由测试直接覆盖。

其余没覆盖到的，都是需要进程之外的东西才能触发的分支。`ai.mbt` 里的 `analyze`——唯一与 DeepSeek 通信的函数——从未被调用，因为任何测试都不允许访问真实 API；`parser.mbt` 和 `runner.mbt` 的标准输入路径没有被触及，因为每个测试都指定了文件；`diagnostics.mbt` 则留着测试套件无法构造出来的那些解析错误分支和限制类型。

`parser.mbt` 剩下的那些点大多在快路径里，而它们之所以没被执行，是因为一旦被执行就说明有 bug：两个循环末尾的 `abort` 行（那两个循环只会通过返回离开），以及字符串末尾把转义序列截断时的兜底判断。剩下的点只有测试套件不携带的文档才够得着——一份超过 64 MiB 输入上限的文档，这正是下一节要说的。

## 性能

`bench/run.sh` 生成三份文档，并分别对发布版构建计时，先格式化再校验：

```sh
bench/run.sh
```

```
moonjson-toolkit 0.1.0
best of 3 runs, times in seconds

file           size       format     validate
small.json     982 B      0.002 s    0.002 s
medium.json    1.1 MB     0.042 s    0.035 s
large.json     9.6 MB     0.304 s    0.248 s
```

这些数字来自 WSL2 下的 Ryzen 9 8940HX，每次运行之间会有一成左右的浮动。文档由
`bench/generate.sh` 生成，基准测试里进仓库的只有脚本：文档是产物而不是源码，已经写进
`.gitignore`。三份文档刻意做成不同的形状——1 KB 的嵌套对象、1 MB 的对象与数组混合、
以及 10 MB 的四十层深链，外加一个六万元素的数组、一个 200×250 的矩阵和一个 25 万字符
的字符串。

十兆字节是这个工具此前根本读不了的大小。库解析器拒绝任何超过 1 MiB 的文档，这个上限
它自己握着，只在文档已经太长时才报告出来，所以现在由 `parser.mbt` 自己读文档，上限
64 MiB。时间也主要花在读上：`parsec/json` 大约每秒读一兆字节，十兆字节就是十秒。
`parser.mbt` 直接按同一套文法，在文档自身的码元上扫描。同一份 `medium.json`，库要
1.21 s，扫描器只要 48 ms，且两者是在同一构建里量的——这就是大文件那一行的三分之一秒
背后的倍数。

扫描器不是对「文档哪里不对」的第二种说法。它不肯接受的一切都会交给库解析器，由后者指出
问题是什么、出在哪里，所以每一条诊断都和从前一模一样。它必须做对的是「哪些文档是好的」，
`parser_differential_wbtest.mbt` 量的正是这一点：在一组文档以及它们每一个单字符改动之上，
两个读取器接受的文档相同，读出的值也相同。

## 技术栈

| 组件 | 用途 |
| ----- | ---- |
| [MoonBit](https://www.moonbitlang.com/) | 整个项目 |
| [`Nanaloveyuki/parsec`](https://mooncakes.io/docs/Nanaloveyuki/parsec) | 解析器组合子，JSON 文法是其中的 `parsec/json` |
| [`oboard/mio`](https://mooncakes.io/docs/oboard/mio) | `--ai` 背后的 HTTP 请求 |
| [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async) | 异步运行时、超时、文件与标准流 IO |
| [`moonbitlang/x`](https://mooncakes.io/docs/moonbitlang/x) | 系统相关的辅助 |
| [Rabbita](https://github.com/moonbit-community/rabbita) | Web 仪表盘，编译成 JavaScript |
| [Apache ECharts](https://echarts.apache.org/) | 柱状图和饼图 |

## 已知限制

- **`--ai` 不看代理设置。** 请求是通过 `mio` 用直连 socket 发出的，它不读 `http_proxy`
  或 `https_proxy`。在只能通过代理访问外网的环境里，`--ai` 会连不上；请在能直连该 API
  的地方运行它，或者自己把流量导过去。工具里的其它部分都能离线工作。

- **Linux 之外的颜色判断退回到环境变量。** 在 Linux 上工具会向内核询问标准输出是不是
  终端，所以重定向到文件的文档永远不会被着色。没有 `/proc` 的平台没法在不做平台特定
  系统调用的情况下拿到这个答案，而本项目没有做这些调用，于是那里改用 `TERM` 来判断。
  输出被重定向时 `TERM` 依然是设着的，所以那些平台上的重定向运行可能仍会带上颜色；
  解决办法是 `--no-color` 或 `NO_COLOR=1`，两者在任何地方都有效。

- **键里含 `.`、`[` 或 `]` 时路径有歧义。** 路径是按读起来的样子写的，而不是转义过的，
  所以 `{"a.b": 1}` 和 `{"a": {"b": 1}}` 都产生 `a.b`，而 `{"a[0]": 1}` 与名为 `a` 的
  数组的第一个元素无法区分。用到这些字符的键足够罕见，值得换取可读的形式；真遇到时，
  给它们加引号，或者把路径列表和文档对照着读。

## 依赖与许可证

所有依赖都是 Apache-2.0，这是宽松许可，与本项目自身的许可证兼容：它不是 copyleft，
不要求本项目以同样的条款发布，只要求保留版权与许可声明。整棵依赖树里没有 GPL，也没有
AGPL。

| 依赖 | 版本 | 许可证 |
| ---- | ---- | ------ |
| [`Nanaloveyuki/parsec`](https://mooncakes.io/docs/Nanaloveyuki/parsec) | 0.1.3 | Apache-2.0 |
| [`oboard/mio`](https://mooncakes.io/docs/oboard/mio) | 0.5.4 | Apache-2.0 |
| [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async) | 0.22.1 | Apache-2.0 |
| [`moonbitlang/x`](https://mooncakes.io/docs/moonbitlang/x) | 0.5.5 | Apache-2.0 |
| [`moonbit-community/rabbita`](https://mooncakes.io/docs/moonbit-community/rabbita) | 0.15.2 | Apache-2.0 |

前四个是命令行工具的依赖，声明在 `moon.mod` 里；Rabbita 是仪表盘的依赖，声明在
`frontend/moon.mod` 里。各包的许可证取自它在 Mooncakes 上自己那份 `moon.mod` 中的声
明，`.mooncakes/` 下随包拉取的那份也是一样的说法。

它们带进来的依赖同样是 Apache-2.0：`oboard/mio` 需要的 `bikallem/compress@0.3.4` 和
`bikallem/blit@0.2.2`，以及 Rabbita 锁定的 `moonbitlang/async@0.20.5`。在任一模块下运行
`moon tree` 都能打印出完整的依赖树。构建仪表盘时还会在命令行用到
[`moonbit-community/warren`](https://mooncakes.io/docs/moonbit-community/warren)
（Apache-2.0），图表库则是 vendor 进来的：见下方许可证一节。

## 许可证

Apache-2.0。ECharts 同样以 Apache-2.0 授权，其许可文本随 vendor 的 bundle 一起放在
`frontend/public/echarts.LICENSE.txt`。
