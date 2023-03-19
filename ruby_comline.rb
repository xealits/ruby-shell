#!/usr/bin/ruby
##
# a shell

require 'open3'
require 'irb'
require 'readline'

$x = 55
x = 5

$prompt = '#{$last_exit_code.to_s.rjust 3} stdin> '
$last_exit_code = 0

$cwd_history = [Dir.pwd]
$cwd_max_length = 5
$home_dir_aliases = ['~', '']

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

def console (at_binding = nil)
  while usr_command = Readline.readline(eval('"' + $prompt + '"'), true)

    # special control cases
    if usr_command.strip.empty?
      next
    elsif usr_command.strip[...4] == 'exit'
      return usr_command.strip[4...].to_i

    elsif usr_command.strip[...3] == 'irb'
      at_binding.irb
      next

    elsif usr_command.strip[...2] == 'cd' # turn it into z?
      directory = usr_command.strip[2...].strip
      cwd directory
      next
    end

    # the shell command
    # eval the ruby code in the command, like: ls #{x+5}
    if at_binding
      usr_command = at_binding.eval('"' + usr_command + '"')
    else
      usr_command = eval('"' + usr_command + '"')
    end

    # exec the system process
    begin
      stdin, stdout, stderr, wait_thr = Open3.popen3(usr_command)
      $last_exit_code = wait_thr.value.exitstatus
      puts "#{stdout.read} #{stderr.read}"

    rescue Errno::ENOENT => error
      # command not found
      #puts "command not found: #{usr_command}"
      puts error.message
    end
  end
end

exit_code = console binding
Kernel.exit exit_code
