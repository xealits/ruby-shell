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

Completion is still wonky.


## Try next

Ruby shell & multiple terminals -- try to bootstrap a cluster of computers over ssh?
I.e. instead of having another tool to execute user commands remotely, use ssh.
It's not some containers orchestration.
Just explore what can be done with a normal-language shell.

* Check Ruby’s SSH lib.
* connect & disconnect comline to a process std streams & working directory:
  separate command & file history. It means having a proper comline class.
* Is it possible to change the environment variables of a running process?

Each ssh session needs to know its ID etc. Which should be simple like `#{session_id}` etc.

Sending comlines to a process stdin—it is different from calling popen3, right?
Or, we call the commands and paste their output to the process?
It’s tricky to mix both. But, with `#{}` I can call a command too.

* what can be tried easily: expose the streams of background processes for
  anything in the comline. I.e. `ls > #{proc_in(5)}` won't work now,
  because there is no such pipe from shell into Ruby. So, `proc_in` should create
  a temporary pipe, one end of which is open into the standard stream that is
  saved somewhere in Ruby.
* if I launch a remote process, can I access its streams in comline easily?
  As if the streams are forwarded over SSH.

Also check mounting over ssh: sshfs.

Maybe queue computing jobs? But no, it is somewhat a full application, 
with a load balancer etc. It's not just a better script.


### Posting on rubygems

About ready to go, the spec file is there.

But also, I am not sure why I keep Gemfile and lock file in git.
Following [Yehuda Katz](https://yehudakatz.com/2010/12/16/clarifying-the-roles-of-the-gemspec-and-gemfile/),
I don't need it, because it is a gem, not an app with dependencies.
But the executable is kind of an app?
In any case, I don't have any dependencies, except Ruby version,
so it does not matter that much now. (My MacOS does run an old Ruby 2.6 which cannot run this gem.)


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
