#!/usr/bin/ruby
##
# a shell

require 'open3'
#require 'tty-command'
require 'irb'
require 'readline'

#$tty_cmd = TTY::Command.new

$x = 55
x = 5

$prompt = '#{$last_exit_code.to_s.rjust 3} stdin> '
$last_exit_code = 0
$running_processes = []

$cwd_history = [Dir.pwd]
$cwd_max_length = 5
$home_dir_aliases = ['~', '']

$global_binding  = binding
$current_binding = $global_binding
#puts "#{$global_binding} #{$current_binding}"

def proc_pid proc_num
  if proc_num > $running_processes.length
    puts "proc_num > $running_processes.length"
  end

  return $running_processes[proc_num][3][:pid]
end

def update_cwd_history prev_dir
    # update cwd history
    # make place in history, if it's at max
    if $cwd_history.count >= $cwd_max_length
      $cwd_history.shift
    end

    # push new element, if it is new
    if prev_dir != $cwd_history[-1]
      $cwd_history.push prev_dir
    end
end

def cwd_chdir directory
  #
  begin
    prev_dir = Dir.pwd
    Dir.chdir directory
    update_cwd_history prev_dir

  rescue Errno::ENOENT => error
    puts error.message
  end
end

def cwd dir
  dir.strip!

  # special cases
  if $home_dir_aliases.include? dir
    directory = Dir.home

  # prev dir
  elsif dir == '-'
    directory = $cwd_history[-1]

  # if directory does not exist, try to match it to one in history
  elsif (!Dir.exists? dir)
    match = $cwd_history.find {|e| e.include? dir}
    directory = if match then match else dir end
  else
    directory = dir
  end

  cwd_chdir directory
end

def clear_dead_jobs
  n_jobs = $running_processes.length

  $running_processes.reject! do |p|
    isdead = !p[3].alive?
    $last_exit_code = p[3].value.exitstatus if isdead
    isdead # the return value of the block, that makes reject! reject
  end

  puts "cleared #{n_jobs - $running_processes.length} dead jobs"
end

# make the shell continue if "terminal stop" SIGTSTP Ctrl-Z is sent (the current process should go to background and sleep)
Signal.trap('TSTP') {
  puts 'received TSTP, (if any) current proc went into background'
  #console binding # this launches a new console, inside of the original that got stopped
  # return from the stopped binding
  #puts "#{$global_binding} #{$current_binding}"

  if $current_binding != $global_binding
    proc_binding = $current_binding
    $current_binding = $global_binding
    proc_binding.eval("return 0")
  end

}

def read_fd fd
  # so, it's like just a pipe
  while s = fd.gets
    puts s
  end
end

def is_int? s
  true if Integer(s) rescue false
end

# TODO turn it into an autonomous process signal handler
# without the external kill command
def shell_kill_cmd command
  # this is a mess:
  # command is a list of user_command.split
  # and shell_kill_cmd is called only if the first word in the command is kill

  # substitute all occurances of %i job number with the PID if possible
  command.map! do |e|
    if e[0] == '%' and is_int?(e[1..])
      i = Integer(e[1..])
      if $running_processes[i]
        $running_processes[i][3][:pid]
      else
        STDERR.puts "no job process is running at index #{i}"
        return
      end
    else
      # if it is not a %i -- just leave it as is
      e
    end
  end

  # rebuild the command string and launch the external kill command
  usr_command = command.join ' '
  puts usr_command
  _, stdout, stderr, wait_thr = Open3.popen3(usr_command)
  $last_exit_code = wait_thr.value.exitstatus
  puts "#{stdout.read} #{stderr.read}"
  return $last_exit_code
end

def eval_cmd usr_command, at_binding
  usr_command.strip!

  # special control cases
  command = usr_command.split
  if command[0] == 'irb'
    at_binding.irb
    return

  elsif command[0] == 'cd'
    directory = usr_command.strip[2...].strip
    cwd directory
    return

  elsif command[0] == 'jobs'
    if command[1] == 'clear'
      clear_dead_jobs

    # if it acts on a process number
    elsif command[1] and /(\D+)/.match(command[1]).nil?
      proc_num = Integer(command[1])
      if proc_num >= $running_processes.length
        puts "there is no background process #{proc_num} see: jobs"
        return
      end

      field = command[2]
      if field == 'stdout'
        puts "proc #{proc_num} stdout:"
        puts $running_processes[proc_num][1].read
      elsif field == 'stderr'
        puts "proc #{proc_num} stdout:"
        $running_processes[proc_num][2].read
      end

    else # print exiting processes/jobs
      $running_processes.each_with_index {|p, i| puts "#{i}: #{p[3][:pid]} #{p[3]}"}
    end
    return

  elsif command[0] == 'kill' # handle %1 sort of ID
    return shell_kill_cmd command
  end

  # the shell command
  # eval the ruby code in the command, like: ls #{x+5}
  # TODO: the following eval breaks if the command line contains ""
  if at_binding
    usr_command = at_binding.eval('"' + usr_command + '"')
  else
    usr_command = eval('"' + usr_command + '"')
  end
  # TODO: so, how good is this for actual Ruby code? How does it work now?
  # There is the environment of Ruby interpreter, which spawns the system commands.
  # The irb keyword gets you straight into the Ruby interpreter.
  # You can run some Ruby code in #{} and get the outputs.
  # How to get the data back: from the system commands to Ruby?
  # The protocol interface, serialisation, should pop up somewhere there.
  # System commands return some parseable data, Ruby easily picks it up.

  # exec the system process
  begin
    # this works for vim, but no control over streams:
    #$last_exit_code = system(usr_command)
    spawn_process = false
    usr_command, spawn_process = usr_command[...-1], true if usr_command.split[-1] == '&'

    if spawn_process

      stdin, stdout, stderr, wait_thr = Open3.popen3(usr_command)
      puts "stdin.tty? #{stdin.tty?}"
      # TODO this won't work for vim
      #      I guess I need a thread for spawned background processes

      # let's save it as a running proc
      $running_processes.append [stdin, stdout, stderr, wait_thr]

      puts "launched a process #{wait_thr[:pid]}"
      # TODO: what if the process quickly exits, like stdbuf -o0 sh ?
      # then it shows up as dead in jobs listing
      # and I save its stdout and stdin, but there is no command to display them?
      # the only command I have is jobs clear.
      #
      # Should there be a common way to connect to stdout of a running process
      # and log it into some ringbuffer/pipe like data structure?
      # I.e. the point is to just work with Linux and /proc instead of creating
      # a new layer of jobs management system in the shell.
      # Linux runs processes by their PIDs. What's needed are some domain names,
      # like unit name in systemd, groups of processes, etc. Also resources:
      # ports, sockets, files, locks.
      #
      # Then also, attach event handlers to that data structure?
      # What Open3.popen3 returns? Are these some stream generators or already
      # the whole text from the file descriptors?
      # yeah, its an IO object:
      #   0 stdin> jobs 0 stdout
      #   proc 0 stdout:
      #   #<IO:0x000077c296ed2508>
      return

    else
      # save this binding point and follow the command
      $current_binding = binding #TODO: why do I save the binding here? for Ctrl-C?

      # just use Process.spawn
      pid = Process.spawn(usr_command, :in=>STDIN, :out=>STDOUT, :err=>STDERR)
      Process.wait(pid)
      $last_exit_code = $?.exitstatus

      $current_binding = $global_binding # restore
      return $last_exit_code
    end

    # TODO: retry this:
    # does not really work:
    # xterm, screen, etc launch something and do not matter themselves
    # how to get the pid of the screen session, shell/fish that they opened?
    # this works:
    #   0 stdin> stdbuf -o0 sh
    # launched a process 24148
    #   0 stdin> xterm -fg grey -bg black -e ./ruby_read_fd.rb 24148
    # launched a process 24151
    #   0 stdin> xterm -fg grey -bg black -e 'cat >> /proc/24148/fd/0'
    # launched a process 24154

  rescue Errno::ENOENT => error
    # command not found
    #puts "command not found: #{usr_command}"
    puts error.message
  end
end

def console (at_binding = nil)
  while usr_command = Readline.readline(eval('"' + $prompt + '"'))
    #puts "#{$global_binding} #{$current_binding} | #{at_binding}"
    if usr_command.strip.empty?
      next
    end

    # if it is not empty -- add it to history
    # or TODO: add it if it succeeded
    Readline::HISTORY.push usr_command
    if usr_command.strip[...4] == 'exit'
      # clear dead jobs and kill the running background processes
      clear_dead_jobs

      if $running_processes.length > 0
        puts "killing #{$running_processes.length} active backgroun processes"
        $running_processes.each {|_, _, _, wait_thr| `kill -KILL #{wait_thr[:pid]}`}
        clear_dead_jobs
      end

      return usr_command.strip[4...].to_i
    else
      eval_cmd usr_command, at_binding
    end
  end
end

exit_code = console $global_binding
$running_processes.each {|p| exit_code = p[3].value.exitstatus}
Kernel.exit exit_code
