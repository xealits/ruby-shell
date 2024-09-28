A simple shell program in Ruby: run external commands, spawn processes and manage them.

```
ruby -Ilib bin/comline
```

Or build and install the gem (it is not on rubygems.org yet):

```
gem build ruby_shell.gemspec
gem install --user-install ./ruby_shell-0.1.0.gem 
gem uninstall ruby_shell
```

It simply `eval`s the input string, to execute Ruby code in `#{...}` expressions.
Then it spawns a process with the result as the command line.

It is a toy project, just to try Ruby in shell programming, as it suits it well.
The idea is to have a more normal language for shell, and try it out on process
management tasks: spawn multiple processes, manipulate their file descriptors,
connect `stdin` and `stdouts` as pipes, etc. It should be possible to spawn
multiple `xterm` running the shell with the same `stdin`. It should be easy to
browse their environment, pick up their logs in `stdout` and `stderr`, etc.
It might be worth to try some process launch conditions, react to events in
filesystem changes, have some FSM on the running processes.

# Notes

This works:

```
   0 stdin> stdbuf -o0 sh &
 launched a process 24148
   0 stdin> xterm -fg grey -bg black -e ./ruby_read_fd.rb #{proc_pid(0)} &
 launched a process 24151
   0 stdin> xterm -fg grey -bg black -e 'cat >> /proc/#{proc_pid(0)}/fd/0' &
 launched a process 24154
  0 stdin> cat >> /proc/#{proc_pid(0)}/fd/0

  0 stdin> alias stdsh stdbuf -o0 sh
  0 stdin> stdsh &
```

Also:

```
alias ls ls --color=auto
```

To kill a background process, use its `%<number>` from the `jobs` list:
`kill %0` etc.

Somehow, `kill 0` kills the process and also terminates the shell.
I.e. `popen3("kill 0")` terminates the Ruby interpreter?
