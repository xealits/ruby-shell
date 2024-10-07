A simple shell program in Ruby: run external commands, spawn processes and manage them.

```
ruby -Ilib bin/comline

screen -S foobar ruby -Ilib bin/comline --name foobar
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

* actually, completion could be done like fzf or the [`ncurses_menu`](https://github.com/xealits/curses_menu)


## Do list

Ruby shell & multiple terminals -- try to bootstrap a cluster of computers over ssh?
I.e. instead of having another tool to execute user commands remotely, use ssh.
It's not some containers orchestration.
Just explore what can be done with a normal-language shell.

* Check Ruby’s SSH lib.
* connect & disconnect comline to a process std streams & working directory:
  separate command & file history. It means having a proper comline class.
  + turned Comline into a class, just in case. There are questions here.
    It's about who handles the actual UI, like with the terminal VS stdandard streams.
    Aside of the streams, there are signals, and also the `Readline` completion proc.
* in general, what's next? The jobs management system - what is it about? Erlang OTP?
  + also, since it is a shell, it needs some capability for introspection
    and exploratory presentation to the user -- that was one of the main problem I had to deal with way back

* check serialisation in Ruby
* check InfluxDB & its logs in Ruby
  + and is there something nicer than Graphana to show the data?
  + and it goes to OPC in Ruby (HTTP is there, sure).
    OPC or something OPC-like could actually work for the shell with its subprocesses.
    I.e. now it gets names (sort of domain names for processes), hence you can
    address processes like: host.computer/comline_foo/process_x.
    Nested comlines and processes may follow some OPC-like standard for nested
    browseable interfaces to whatever states they expose.

* try connecting to a serial port, Arduino or Ti or whatever,
  with the [uart](https://tenderlovemaking.com/2024/02/16/using-serial-ports-with-ruby/) gem
* Is it possible to change the environment variables of a running process?
  [With `prctl`](https://unix.stackexchange.com/questions/302948/change-proc-pid-environ-after-process-start).
  It's pretty complex. The standard `/proc/<pid>/environ` contains the original environment.
  (Again, a typical unfinished Unix bit: the system does not expect processes to have their domain name spaces.
   One OS is like one program. I.e. it is not a system of programs, but a system of _commands_ of one program.
   Though, a system of programs turns into one program anyway.)

Each ssh session needs to know its ID etc. Which should be simple like `#{session_id}` etc.

Sending comlines to a process stdin—it is different from calling popen3, right?
Or, we call the commands and paste their output to the process?
It’s tricky to mix both. But, with `#{}` I can call a command too.

* what can be tried easily: expose the streams of background processes for
  anything in the comline. I.e. `ls > #{proc_in(5)}` won't work now,
  because there is no such pipe from shell into Ruby. So, `proc_in` should create
  a temporary pipe, one end of which is open into the standard stream that is
  saved somewhere in Ruby.
  + firstly, writing to a `/proc/<pid>/fd/0` works fine

* if I launch a remote process, can I access its streams in comline easily?
  As if the streams are forwarded over SSH.
  + writing over SSH should be easy like
    ```
    $ tar -cf - /path/to/backup/dir | ssh remotehost "cat - > backupfile.tar"
    ```

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
   0 stdin> xterm -fg grey -bg black -e lib/ruby_read_fd.rb #{proc_pid(0)} &
 launched a process 24151
   0 stdin> xterm -fg grey -bg black -e 'cat >> /proc/#{proc_pid(0)}/fd/0' &
 launched a process 24154
  0 stdin> cat >> /proc/#{proc_pid(0)}/fd/0

  0 stdin> alias stdsh stdbuf -o0 sh
  0 stdin> stdsh &
```

```
  0 stdin> cat > temp_foo &
stdin.tty? false
launched a process 9902
  0 stdin>
  0 stdin> echo "hello" > #{proc_stdin proc_pid 0}
  0 stdin> echo "world" > #{proc_stdin proc_pid 0}
  0 stdin> echo "this is Ruby shell" > #{proc_stdin proc_pid 0}
  0 stdin> cat temp_foo
hello
world
this is Ruby shell
  0 stdin> jobs
0: 9902 cat > temp_foo  #<Process::Waiter:0x000070d9beeb69b0 sleep>
  0 stdin> kill %0
kill 9902
  0 stdin> jobs
0: 9902 cat > temp_foo  #<Process::Waiter:0x000070d9beeb69b0 dead>
  0 stdin> jobs clear
cleared 1 dead jobs
    stdin> jobs
    stdin> exit
```

Same things:

```
  0 stdin> echo "world" > #{proc_stdin proc_pid 0}
  0 stdin> echo "world" > /proc/#{proc_pid 0}/fd/0
```

Also:

```
alias ls ls --color=auto
```

To kill a background process, use its `%<number>` from the `jobs` list:
`kill %0` etc.

Somehow, `kill 0` kills the process and also terminates the shell.
I.e. `popen3("kill 0")` terminates the Ruby interpreter?

Change the delimiters of 0-separated strings in proc:

```
xargs -0 -L1 -a /proc/self/environ
```

Hot-reloading `Comline` class somehow does not work:

```
  0      foo stdin> echo "#{load 'lib/ruby_shell.rb'}"
true
  0      foo stdin>
# here I changed the rjsut to ljust in the prompt
```
