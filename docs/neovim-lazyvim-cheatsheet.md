# Neovim / LazyVim Cheat Sheet

## Most important idea

Neovim has modes:

```text
Normal mode  = moving/commands
Insert mode  = typing text
Visual mode  = selecting text
Command mode = : commands
```

If you feel lost, press `Esc` a couple times.

---

## Mode basics

```text
i        enter insert mode
Esc      return to normal mode
v        visual select
V        visual line select
:        command mode
```

---

## Save / quit

```text
:w       save
:q       quit
:wq      save and quit
:q!      quit without saving
:qa      quit all
Ctrl-s   save, LazyVim shortcut
```

---

## Movement

```text
h        left
j        down
k        up
l        right

w        next word
b        previous word
0        start of line
$        end of line
gg       top of file
G        bottom of file
```

Arrow keys also work.

---

## Open/find files

```text
Space f f    find files
Space f F    find files from current directory
Space e      file explorer
Space /      search text in project
Space s g    search text in project
```

In picker:

```text
type text    filter results
Enter        open selected file
Esc          close picker
Alt-h        toggle hidden files
Alt-i        toggle ignored files
```

---

## Explorer

```text
Space e      open explorer

j/k          move down/up
l            open/expand
h            collapse
Enter        open file
q            close explorer
H            toggle hidden files
I            toggle ignored files
```

---

## Editing

```text
x        delete character
dd       delete line
yy       copy line
p        paste
u        undo
Ctrl-r   redo
```

Change text:

```text
cw       change word
ci"      change inside quotes
ci(      change inside parentheses
```

---

## Copy/paste system clipboard

Since clipboard is configured:

```text
V        select lines
y        copy
p        paste
```

If needed explicitly:

```text
"+y      copy to system clipboard
"+p      paste from system clipboard
```

---

## Terminal inside Neovim

```text
Space t t    open terminal
Space f t    terminal at project root
Space f T    terminal at current directory
```

Inside terminal:

```text
Esc Esc      leave terminal mode
```

---

## Splits/windows

Custom resize keys that avoid your Hyprland `Ctrl-w` conflict:

```text
Alt-Left     make split narrower
Alt-Right    make split wider
Alt-Up       make split shorter
Alt-Down     make split taller
Space w =    equalize window sizes
```

LazyVim split keys:

```text
Space -      horizontal split
Space |      vertical split
Space w d    close window
```

---

## Help/menu discovery

Press:

```text
Space
```

Then pause. LazyVim shows a menu of available commands.

This is one of the best ways to learn LazyVim.

---

## First things to memorize

Only memorize these first:

```text
i           type
Esc         stop typing
:w          save
:q          quit
Space f f   find file
Space e     explorer
Space /     search project
u           undo
dd          delete line
yy          copy line
p           paste
```
